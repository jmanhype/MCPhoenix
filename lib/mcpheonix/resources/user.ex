defmodule MCPheonix.Resources.User do
  @moduledoc """
  User resource for the MCPheonix application.
  
  This module defines the User entity and its operations.
  """
  require Logger
  alias MCPheonix.Events.Broker
  
  @doc """
  User struct representing a user in the system.
  """
  defstruct [
    :id,
    :username,
    :email,
    :full_name,
    :active,
    :created_at,
    :updated_at
  ]
  
  @type t :: %__MODULE__{
    id: String.t(),
    username: String.t(),
    email: String.t(),
    full_name: String.t() | nil,
    active: boolean(),
    created_at: DateTime.t(),
    updated_at: DateTime.t()
  }
  
  # In-memory storage for users
  @users_table :users_table
  
  @doc """
  Initializes the user storage.
  """
  def init do
    :ets.new(@users_table, [:set, :public, :named_table])
    :ok
  end
  
  @doc """
  Registers a new user.
  
  ## Parameters
    * `attrs` - User attributes
      * `:username` - The username (required)
      * `:email` - The email address (required)
      * `:full_name` - The full name (optional)
      * `:password` - The password (required, not stored)
  
  ## Returns
    * `{:ok, user}` - The user was registered successfully
    * `{:error, reason}` - The registration failed
  """
  def register(attrs) when is_map(attrs) do
    # Extract attributes
    username = Map.get(attrs, :username)
    email = Map.get(attrs, :email)
    full_name = Map.get(attrs, :full_name)
    password = Map.get(attrs, :password)
    
    # Validate required fields
    cond do
      is_nil(username) or String.length(username) < 3 or String.length(username) > 50 ->
        {:error, "Username must be between 3 and 50 characters"}
        
      is_nil(email) or String.length(email) < 5 or String.length(email) > 255 ->
        {:error, "Email must be between 5 and 255 characters"}
        
      is_nil(password) or String.length(password) < 8 ->
        {:error, "Password must be at least 8 characters"}
        
      not is_nil(full_name) and String.length(full_name) > 255 ->
        {:error, "Full name must be less than 255 characters"}
        
      # Check if username is already taken
      username_exists?(username) ->
        {:error, "Username is already taken"}
        
      # Check if email is already taken
      email_exists?(email) ->
        {:error, "Email is already taken"}
        
      true ->
        # Create user
        user = %__MODULE__{
          id: UUID.uuid4(),
          username: username,
          email: email,
          full_name: full_name,
          active: true,
          created_at: DateTime.utc_now(),
          updated_at: DateTime.utc_now()
        }
        
        # Store user
        :ets.insert(@users_table, {user.id, user})
        
        # We would normally hash the password here, but for this simplified example,
        # we'll just log that we received it
        Logger.info("Would hash password: #{password}")
        
        # Publish event
        Broker.publish("resources:user:registered", %{
          id: user.id,
          username: user.username,
          timestamp: DateTime.utc_now()
        })
        
        {:ok, user}
    end
  end
  
  @doc """
  Gets a user by ID.
  
  ## Parameters
    * `id` - The ID of the user to get
  
  ## Returns
    * `{:ok, user}` - The user was found
    * `{:error, reason}` - The user was not found
  """
  def get(id) when is_binary(id) do
    case :ets.lookup(@users_table, id) do
      [{^id, user}] -> {:ok, user}
      [] -> {:error, "User not found"}
    end
  end
  
  @doc """
  Lists all users.
  
  ## Parameters
    * `opts` - Options for listing users
      * `:active_only` - If true, only return active users
  
  ## Returns
    * List of users
  """
  def list(opts \\ []) do
    active_only = Keyword.get(opts, :active_only, false)
    
    # Get all users
    all_users = :ets.tab2list(@users_table)
      |> Enum.map(fn {_id, user} -> user end)
    
    # Filter by active if specified
    if active_only do
      Enum.filter(all_users, fn user -> user.active end)
    else
      all_users
    end
  end
  
  @doc """
  Activates a user.
  
  ## Parameters
    * `id` - The ID of the user to activate
  
  ## Returns
    * `{:ok, user}` - The user was activated successfully
    * `{:error, reason}` - The activation failed
  """
  def activate(id) when is_binary(id) do
    case get(id) do
      {:ok, user} ->
        if user.active do
          {:ok, user}
        else
          # Create updated user
          updated_user = %{user |
            active: true,
            updated_at: DateTime.utc_now()
          }
          
          # Store updated user
          :ets.insert(@users_table, {id, updated_user})
          
          # Publish event
          Broker.publish("resources:user:activated", %{
            id: id,
            username: user.username,
            timestamp: DateTime.utc_now()
          })
          
          {:ok, updated_user}
        end
        
      error -> error
    end
  end
  
  @doc """
  Deactivates a user.
  
  ## Parameters
    * `id` - The ID of the user to deactivate
  
  ## Returns
    * `{:ok, user}` - The user was deactivated successfully
    * `{:error, reason}` - The deactivation failed
  """
  def deactivate(id) when is_binary(id) do
    case get(id) do
      {:ok, user} ->
        if not user.active do
          {:ok, user}
        else
          # Create updated user
          updated_user = %{user |
            active: false,
            updated_at: DateTime.utc_now()
          }
          
          # Store updated user
          :ets.insert(@users_table, {id, updated_user})
          
          # Publish event
          Broker.publish("resources:user:deactivated", %{
            id: id,
            username: user.username,
            timestamp: DateTime.utc_now()
          })
          
          {:ok, updated_user}
        end
        
      error -> error
    end
  end
  
  # Private functions
  
  defp username_exists?(username) do
    :ets.tab2list(@users_table)
    |> Enum.any?(fn {_id, user} -> user.username == username end)
  end
  
  defp email_exists?(email) do
    :ets.tab2list(@users_table)
    |> Enum.any?(fn {_id, user} -> user.email == email end)
  end
  
  @doc """
  Resource name for MCP protocol.
  """
  def __resource_name__, do: "user"
  
  @doc """
  Primary actions for MCP protocol.
  """
  def __primary_actions__ do
    [
      list: %{
        name: :list,
        arguments: [
          active_only: %{
            type: :boolean,
            allow_nil?: true
          }
        ],
        accept: []
      },
      register: %{
        name: :register,
        arguments: [
          password: %{
            type: :string,
            allow_nil?: false
          }
        ],
        accept: [:username, :email, :full_name]
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
      activate: %{
        name: :activate,
        arguments: [
          id: %{
            type: :string,
            allow_nil?: false
          }
        ],
        accept: []
      },
      deactivate: %{
        name: :deactivate,
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
end 