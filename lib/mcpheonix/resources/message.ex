defmodule MCPheonix.Resources.Message do
  @moduledoc """
  Message resource for the MCPheonix application.
  
  This module defines the Message entity and its operations.
  """
  require Logger
  alias MCPheonix.Events.Broker
  
  @doc """
  Message struct representing a user message.
  """
  defstruct [
    :id,
    :content,
    :user_id,
    :created_at,
    :updated_at
  ]
  
  @type t :: %__MODULE__{
    id: String.t(),
    content: String.t(),
    user_id: String.t(),
    created_at: DateTime.t(),
    updated_at: DateTime.t()
  }
  
  # In-memory storage for messages
  @messages_table :messages_table
  
  @doc """
  Initializes the message storage.
  """
  def init do
    :ets.new(@messages_table, [:set, :public, :named_table])
    :ok
  end
  
  @doc """
  Creates a new message.
  
  ## Parameters
    * `user_id` - The ID of the user who created the message
    * `content` - The content of the message
  
  ## Returns
    * `{:ok, message}` - The message was created successfully
    * `{:error, reason}` - The message creation failed
  """
  def create(user_id, content) when is_binary(user_id) and is_binary(content) do
    # Validate content
    if String.length(content) < 1 or String.length(content) > 5000 do
      {:error, "Content must be between 1 and 5000 characters"}
    else
      # Create message
      message = %__MODULE__{
        id: UUID.uuid4(),
        content: content,
        user_id: user_id,
        created_at: DateTime.utc_now(),
        updated_at: DateTime.utc_now()
      }
      
      # Store message
      :ets.insert(@messages_table, {message.id, message})
      
      # Publish event
      Broker.publish("resources:message:created", %{
        id: message.id,
        user_id: user_id,
        content: content,
        timestamp: DateTime.utc_now()
      })
      
      {:ok, message}
    end
  end
  
  @doc """
  Gets a message by ID.
  
  ## Parameters
    * `id` - The ID of the message to get
  
  ## Returns
    * `{:ok, message}` - The message was found
    * `{:error, reason}` - The message was not found
  """
  def get(id) when is_binary(id) do
    case :ets.lookup(@messages_table, id) do
      [{^id, message}] -> {:ok, message}
      [] -> {:error, "Message not found"}
    end
  end
  
  @doc """
  Lists all messages.
  
  ## Parameters
    * `opts` - Options for listing messages
      * `:created_after` - Only return messages created after this datetime
  
  ## Returns
    * List of messages
  """
  def list(opts \\ []) do
    created_after = Keyword.get(opts, :created_after)
    
    # Get all messages
    all_messages = :ets.tab2list(@messages_table)
      |> Enum.map(fn {_id, message} -> message end)
    
    # Filter by created_after if specified
    if created_after do
      Enum.filter(all_messages, fn message ->
        DateTime.compare(message.created_at, created_after) == :gt
      end)
    else
      all_messages
    end
  end
  
  @doc """
  Updates a message.
  
  ## Parameters
    * `id` - The ID of the message to update
    * `attrs` - The attributes to update
  
  ## Returns
    * `{:ok, message}` - The message was updated successfully
    * `{:error, reason}` - The message update failed
  """
  def update(id, attrs) when is_binary(id) and is_map(attrs) do
    case get(id) do
      {:ok, message} ->
        # Update content if provided
        content = Map.get(attrs, :content, message.content)
        
        # Validate content
        if String.length(content) < 1 or String.length(content) > 5000 do
          {:error, "Content must be between 1 and 5000 characters"}
        else
          # Create updated message
          updated_message = %{message |
            content: content,
            updated_at: DateTime.utc_now()
          }
          
          # Store updated message
          :ets.insert(@messages_table, {id, updated_message})
          
          # Publish event
          Broker.publish("resources:message:updated", %{
            id: id,
            content: content,
            timestamp: DateTime.utc_now()
          })
          
          {:ok, updated_message}
        end
        
      error -> error
    end
  end
  
  @doc """
  Resource name for MCP protocol.
  """
  def __resource_name__, do: "message"
  
  @doc """
  Primary actions for MCP protocol.
  """
  def __primary_actions__ do
    [
      list: %{
        name: :list,
        arguments: [
          created_after: %{
            type: :utc_datetime,
            allow_nil?: true
          }
        ],
        accept: []
      },
      post: %{
        name: :post,
        arguments: [],
        accept: [:content, :user_id]
      },
      read: %{
        name: :read,
        arguments: [
          id: %{
            type: :string,
            allow_nil?: false
          }
        ],
        accept: []
      }
    ]
  end
  
  @doc """
  All actions for MCP protocol.
  """
  def __actions__ do
    [
      edit: %{
        name: :edit,
        arguments: [
          id: %{
            type: :string,
            allow_nil?: false
          }
        ],
        accept: [:content]
      }
    ]
  end
end 