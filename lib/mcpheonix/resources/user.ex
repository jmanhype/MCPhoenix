defmodule MCPheonix.Resources.User do
  @moduledoc """
  User resource for the MCPheonix application.
  
  This module defines the User entity and its operations.
  """
  use Ash.Resource,
    data_layer: Ash.DataLayer.Ets,
    extensions: [
      AshJsonApi.Resource
    ]
    
  attributes do
    uuid_primary_key :id
    
    attribute :username, :string do
      allow_nil? false
      constraints [min_length: 3, max_length: 50]
    end
    
    attribute :email, :string do
      allow_nil? false
      constraints [max_length: 255]
    end
    
    attribute :full_name, :string do
      constraints [max_length: 255]
    end
    
    attribute :active, :boolean do
      default true
    end
    
    attribute :created_at, :utc_datetime do
      default &DateTime.utc_now/0
      allow_nil? false
    end
    
    attribute :updated_at, :utc_datetime do
      default &DateTime.utc_now/0
      allow_nil? false
    end
  end
  
  relationships do
    has_many :messages, MCPheonix.Resources.Message
  end
  
  actions do
    defaults [:create, :read, :update, :destroy]
    
    read :list do
      primary? true
      pagination [offset?: true, countable: true]
    end
    
    create :register do
      accept [:username, :email, :full_name]
      argument :password, :string, allow_nil?: false
      
      change set_attribute(:active, true)
      
      # In a real implementation, you would hash the password
      # and store it securely, rather than just logging it
      change fn changeset ->
        password = Ash.Changeset.get_argument(changeset, :password)
        IO.puts("Would hash password: #{password}")
        changeset
      end
    end
    
    update :deactivate do
      accept []
      
      change set_attribute(:active, false)
    end
    
    update :activate do
      accept []
      
      change set_attribute(:active, true)
    end
  end
  
  json_api do
    type "user"
    
    routes do
      base "/users"
      get :read
      index :list
      post :create
      patch :update
      delete :destroy
    end
  end
end 