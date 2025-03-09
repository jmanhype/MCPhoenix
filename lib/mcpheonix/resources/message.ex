defmodule MCPheonix.Resources.Message do
  @moduledoc """
  Message resource for the MCPheonix application.
  
  This module defines the Message entity and its operations.
  """
  use Ash.Resource,
    data_layer: Ash.DataLayer.Ets,
    extensions: [
      AshJsonApi.Resource
    ]
    
  attributes do
    uuid_primary_key :id
    
    attribute :content, :string do
      allow_nil? false
      constraints [min_length: 1, max_length: 5000]
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
    belongs_to :user, MCPheonix.Resources.User do
      allow_nil? false
    end
  end
  
  actions do
    defaults [:create, :read, :update, :destroy]
    
    read :list do
      primary? true
      pagination [offset?: true, countable: true]
      
      filter expr(created_at > ^:created_after)
      argument :created_after, :utc_datetime
    end
    
    create :post do
      accept [:content, :user_id]
      
      # Update timestamps
      change set_attribute(:created_at, DateTime.utc_now())
      change set_attribute(:updated_at, DateTime.utc_now())
    end
    
    update :edit do
      accept [:content]
      
      # Update updated_at timestamp
      change set_attribute(:updated_at, DateTime.utc_now())
    end
  end
  
  code_interface do
    define :get_messages_for_user, args: [:user_id], action: :list
    define :create_message, args: [:user_id, :content], action: :post
  end
  
  json_api do
    type "message"
    
    routes do
      base "/messages"
      get :read
      index :list
      post :create
      patch :update
      delete :destroy
    end
  end
  
  identities do
    identity :unique_id, [:id]
  end
  
  # Add a notification for new messages
  after_action :post, fn _result, changeset ->
    # Publish an event when a message is created
    message = Ash.Changeset.get_data(changeset)
    
    # This is where we'd notify MCP clients about new messages
    MCPheonix.Events.Broker.publish("resources:message:created", %{
      id: message.id,
      user_id: message.user_id,
      content: message.content,
      timestamp: DateTime.utc_now()
    })
    
    :ok
  end
end 