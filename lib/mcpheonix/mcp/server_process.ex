defmodule MCPheonix.MCP.ServerProcess do
  @moduledoc """
  Process module for individual MCP servers.
  
  This module handles the communication with a single MCP server process,
  including sending JSON-RPC requests and handling responses.
  """
  
  use GenServer
  require Logger
  
  # Client API
  
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end
  
  @doc """
  Execute a tool on the MCP server.
  
  ## Parameters
    * `server` - The server process
    * `tool` - The name of the tool to execute
    * `params` - The parameters for the tool
  """
  def execute_tool(server, tool, params) do
    GenServer.call(server, {:execute_tool, tool, params}, 60_000)
  end
  
  # Server Callbacks
  
  @impl true
  def init(opts) do
    server_id = Keyword.fetch!(opts, :server_id)
    command = Keyword.fetch!(opts, :command)
    args = Keyword.get(opts, :args, [])
    env = Keyword.get(opts, :env, %{})
    
    Logger.info("Starting MCP server process: #{server_id}")
    Logger.debug("Command: #{command}, Args: #{inspect(args)}, Env: #{inspect(env)}")
    
    # Convert environment map to list of tuples for Erlang
    env_list = for {key, val} <- env, do: {String.to_charlist(key), String.to_charlist(val)}
    
    # Create a proper command string with arguments
    cmd = ~c"#{command} #{Enum.join(args, " ")}"
    
    # Start the server process with a simpler approach
    port_opts = [
      :binary, 
      :exit_status, 
      :hide, 
      {:env, env_list}
    ]
    
    Logger.debug("Opening port with command: #{inspect(cmd)}")
    
    case Port.open({:spawn, cmd}, port_opts) do
      port when is_port(port) ->
        # Initialize state
        state = %{
          server_id: server_id,
          port: port,
          request_id: 0,
          pending_requests: %{},
          buffer: "",
          tools: %{} # Will be populated when server responds with capabilities
        }
        
        # Send initialize request to get server capabilities
        request = %{
          jsonrpc: "2.0",
          method: "initialize",
          params: %{
            protocolVersion: "0.1.0",
            capabilities: %{
              tools: %{} # Client doesn't have any special tool capabilities
            },
            clientInfo: %{
              name: "MCPheonix",
              version: "0.1.0"
            }
          },
          id: 0
        }
        
        request_json = Jason.encode!(request) <> "\n"
        Port.command(port, request_json)
        
        {:ok, state}
        
      error ->
        Logger.error("Failed to start server process: #{inspect(error)}")
        {:stop, {:error, "Failed to start server process: #{inspect(error)}"}}
    end
  end
  
  @impl true
  def handle_call({:execute_tool, tool, params}, from, state) do
    request_id = state.request_id + 1
    
    # Log available tools before executing
    Logger.debug("Available tools for server #{state.server_id}: #{inspect(state.tools)}")
    Logger.info("Executing tool '#{tool}' on server #{state.server_id} with params: #{inspect(params)}")
    
    # Create JSON-RPC request using official MCP SDK format
    # This must match the CallToolRequestSchema that the server is registered to handle
    request = %{
      jsonrpc: "2.0", 
      method: "tools/call",  # The correct method name from the MCP SDK
      params: %{
        name: tool,        # The SDK expects "name" not "tool"
        arguments: params  # The SDK expects "arguments" not "parameters"
      },
      id: request_id
    }
    
    # Send request to server
    request_json = Jason.encode!(request) <> "\n"
    Logger.debug("Sending request to MCP server: #{inspect(request)}")
    Logger.debug("Raw JSON being sent: #{request_json}")
    Port.command(state.port, request_json)
    
    # Update state with pending request
    state = %{state |
      request_id: request_id,
      pending_requests: Map.put(state.pending_requests, request_id, from)
    }
    
    {:noreply, state}
  end
  
  @impl true
  def handle_info({port, {:data, data}}, %{port: port} = state) do
    # Append new data to buffer
    buffer = state.buffer <> data
    
    # Process complete messages
    {messages, remaining} = split_messages(buffer)
    state = %{state | buffer: remaining}
    
    # Handle each complete message
    state = Enum.reduce(messages, state, &handle_message/2)
    
    {:noreply, state}
  end
  
  @impl true
  def handle_info({port, {:exit_status, status}}, %{port: port} = state) do
    Logger.warning("MCP server #{state.server_id} exited with status: #{status}")
    
    # Reply to all pending requests with error
    Enum.each(state.pending_requests, fn {_id, from} ->
      GenServer.reply(from, {:error, "Server process terminated"})
    end)
    
    {:stop, :normal, state}
  end
  
  # Private Functions
  
  defp split_messages(buffer) do
    case String.split(buffer, "\n", trim: false) do
      [] -> {[], ""}
      parts -> 
        {messages, [remaining]} = Enum.split(parts, -1)
        {Enum.filter(messages, &(&1 != "")), remaining}
    end
  end
  
  defp handle_message(message, state) do
    case Jason.decode(message) do
      {:ok, decoded} ->
        handle_json_message(decoded, state)
        
      {:error, reason} ->
        Logger.error("Failed to decode message from server: #{inspect(reason)}")
        state
    end
  end
  
  defp handle_json_message(%{"jsonrpc" => "2.0", "id" => id} = message, state) do
    case Map.get(state.pending_requests, id) do
      nil ->
        Logger.warning("Received response for unknown request: #{inspect(message)}")
        state
        
      from ->
        # Handle response based on type
        case message do
          # Initialize response
          %{"result" => %{"capabilities" => capabilities}} when id == 0 ->
            # Log the full capabilities for debugging
            Logger.debug("Received initialization response with capabilities: #{inspect(capabilities)}")
            
            # Store tool configurations
            tools = get_in(capabilities, ["tools"]) || %{}
            Logger.debug("Tools from server capabilities: #{inspect(tools)}")
            
            # Always add known tools based on server_id
            # This ensures tools are available even if the server doesn't report them
            additional_tools = case state.server_id do
              "flux" ->
                tools_map = %{
                  "generate" => %{
                    "description" => "Generate an image from a text prompt",
                    "parameters" => %{
                      "prompt" => %{"description" => "Text prompt for image generation", "type" => "string"},
                      "aspect_ratio" => %{"description" => "Aspect ratio of the output image", "type" => "string"},
                      "model" => %{"description" => "Model to use for generation", "type" => "string"},
                      "output" => %{"description" => "Output filename", "type" => "string"}
                    }
                  },
                  "img2img" => %{
                    "description" => "Generate an image using another image as reference",
                    "parameters" => %{
                      "image" => %{"description" => "Input image path", "type" => "string"},
                      "prompt" => %{"description" => "Text prompt for generation", "type" => "string"},
                      "name" => %{"description" => "Name for the generation", "type" => "string"},
                      "strength" => %{"description" => "Generation strength", "type" => "number"}
                    }
                  }
                }
                Logger.debug("Adding flux tools: #{inspect(tools_map)}")
                tools_map
              
              "filesystem" ->
                tools_map = %{
                  "list_files" => %{
                    "description" => "List files in a directory",
                    "parameters" => %{
                      "path" => %{"description" => "Directory path", "type" => "string"}
                    }
                  },
                  "read_file" => %{
                    "description" => "Read a file's contents",
                    "parameters" => %{
                      "path" => %{"description" => "File path", "type" => "string"}
                    }
                  }
                }
                Logger.debug("Adding filesystem tools: #{inspect(tools_map)}")
                tools_map
              
              "dart" ->
                tools_map = %{
                  "create_task" => %{
                    "description" => "Create a new task",
                    "parameters" => %{
                      "title" => %{"description" => "Task title", "type" => "string"},
                      "description" => %{"description" => "Task description", "type" => "string"},
                      "dartboard_duid" => %{"description" => "Dartboard DUID", "type" => "string"},
                      "priority" => %{"description" => "Priority of the task", "type" => "string"},
                      "tags" => %{"description" => "Tags for the task", "type" => "array"},
                      "size" => %{"description" => "Size/complexity of the task (1-5)", "type" => "number"},
                      "assignee_duids" => %{"description" => "List of assignee DUIDs", "type" => "array"},
                      "subscriber_duids" => %{"description" => "List of subscriber DUIDs", "type" => "array"}
                    }
                  },
                  "update_task" => %{
                    "description" => "Update an existing task",
                    "parameters" => %{
                      "duid" => %{"description" => "DUID of the task to update", "type" => "string"},
                      "status_duid" => %{"description" => "New status DUID", "type" => "string"},
                      "title" => %{"description" => "New title for the task", "type" => "string"},
                      "description" => %{"description" => "New description for the task", "type" => "string"},
                      "priority" => %{"description" => "New priority for the task", "type" => "string"}
                    }
                  },
                  "get_default_space" => %{
                    "description" => "Get the default space DUID",
                    "parameters" => %{
                      "dartboard_duid" => %{"description" => "Dartboard DUID", "type" => "string"}
                    }
                  },
                  "get_default_status" => %{
                    "description" => "Get the default status DUIDs",
                    "parameters" => %{
                      "dartboard_duid" => %{"description" => "Dartboard DUID", "type" => "string"}
                    }
                  },
                  "get_dartboards" => %{
                    "description" => "Get available dartboards",
                    "parameters" => %{
                      "space_duid" => %{"description" => "Space DUID to get dartboards from", "type" => "string"}
                    }
                  },
                  "get_folders" => %{
                    "description" => "Get available folders",
                    "parameters" => %{
                      "space_duid" => %{"description" => "Space DUID to get folders from", "type" => "string"}
                    }
                  },
                  "create_folder" => %{
                    "description" => "Create a new folder in a space",
                    "parameters" => %{
                      "space_duid" => %{"description" => "Space DUID to create the folder in", "type" => "string"},
                      "title" => %{"description" => "Title of the folder", "type" => "string"},
                      "description" => %{"description" => "Description of the folder", "type" => "string"},
                      "kind" => %{"description" => "Kind of folder", "type" => "string"}
                    }
                  },
                  "create_doc" => %{
                    "description" => "Create a new document or report",
                    "parameters" => %{
                      "folder_duid" => %{"description" => "Folder DUID to create the document in", "type" => "string"},
                      "title" => %{"description" => "Title of the document", "type" => "string"},
                      "text" => %{"description" => "Content of the document", "type" => "string"},
                      "text_markdown" => %{"description" => "Markdown content of the document", "type" => "string"},
                      "report_kind" => %{"description" => "Kind of report (if creating a report)", "type" => "string"},
                      "editor_duids" => %{"description" => "List of editor DUIDs", "type" => "array"},
                      "subscriber_duids" => %{"description" => "List of subscriber DUIDs", "type" => "array"}
                    }
                  },
                  "create_space" => %{
                    "description" => "Create a new space",
                    "parameters" => %{
                      "title" => %{"description" => "Title of the space", "type" => "string"},
                      "description" => %{"description" => "Description of the space", "type" => "string"},
                      "abrev" => %{"description" => "Short abbreviation for the space", "type" => "string"},
                      "accessible_by_team" => %{"description" => "Whether the space is accessible by the whole team", "type" => "boolean"},
                      "accessible_by_user_duids" => %{"description" => "List of user DUIDs who can access the space", "type" => "array"},
                      "icon_kind" => %{"description" => "Kind of icon to use", "type" => "string"},
                      "icon_name_or_emoji" => %{"description" => "Icon name or emoji character", "type" => "string"},
                      "color_hex" => %{"description" => "Color in hex format (e.g. #FF0000)", "type" => "string"},
                      "sprint_mode" => %{"description" => "Sprint mode for the space", "type" => "string"},
                      "sprint_replicate_on_rollover" => %{"description" => "Whether to replicate sprints on rollover", "type" => "boolean"},
                      "sprint_name_fmt" => %{"description" => "Sprint name format", "type" => "string"}
                    }
                  },
                  "delete_space" => %{
                    "description" => "Delete a space and all its contents",
                    "parameters" => %{
                      "space_duid" => %{"description" => "DUID of the space to delete", "type" => "string"}
                    }
                  }
                }
                Logger.debug("Adding dart tools: #{inspect(tools_map)}")
                tools_map
              
              "discord" ->
                tools_map = %{
                  "send_message" => %{
                    "description" => "Send a message to a Discord channel",
                    "parameters" => %{
                      "channel" => %{"description" => "Channel name", "type" => "string"},
                      "content" => %{"description" => "Message content", "type" => "string"}
                    }
                  }
                }
                Logger.debug("Adding discord tools: #{inspect(tools_map)}")
                tools_map
              
              _ -> 
                Logger.debug("No tools to add for server: #{state.server_id}")
                %{}
            end
            
            # Merge server-reported tools with our additional tools
            merged_tools = Map.merge(tools, additional_tools)
            
            # Log the tools we're registering
            Logger.info("Registered tools for server #{state.server_id}: #{inspect(Map.keys(merged_tools))}")
            
            # Update state with merged tools
            new_state = %{state | tools: merged_tools}
            Logger.debug("Updated state with tools: #{inspect(new_state.tools)}")
            
            GenServer.reply(from, {:ok, capabilities})
            %{new_state | pending_requests: Map.delete(new_state.pending_requests, id)}
            
          # Tool execution response
          %{"result" => result} ->
            Logger.info("Tool execution successful: #{inspect(result)}")
            GenServer.reply(from, {:ok, result})
            %{state | pending_requests: Map.delete(state.pending_requests, id)}
            
          %{"error" => error} ->
            Logger.error("Tool execution failed with error: #{inspect(error)}")
            GenServer.reply(from, {:error, error["message"]})
            %{state | pending_requests: Map.delete(state.pending_requests, id)}
            
          _ ->
            Logger.warning("Received unknown response type: #{inspect(message)}")
            GenServer.reply(from, {:error, "Unknown response type"})
            %{state | pending_requests: Map.delete(state.pending_requests, id)}
        end
    end
  end
  
  defp handle_json_message(%{"jsonrpc" => "2.0", "method" => _method} = message, state) do
    # Handle server-initiated requests (notifications)
    Logger.debug("Received server notification: #{inspect(message)}")
    state
  end
  
  defp handle_json_message(%{"error" => error} = message, state) do
    # Extract request ID from the message
    id = message["id"]
    
    # Log detailed error information
    Logger.error("Error response from server #{state.server_id}: #{inspect(error)}")
    
    case Map.get(state.pending_requests, id) do
      nil ->
        Logger.warning("Received error for unknown request ID: #{id}")
        state
        
      from ->
        # Reply with the error
        GenServer.reply(from, {:error, error["message"]})
        %{state | pending_requests: Map.delete(state.pending_requests, id)}
    end
  end
  
  defp handle_json_message(message, state) do
    Logger.warning("Received invalid JSON-RPC message: #{inspect(message)}")
    state
  end
end 