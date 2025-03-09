defmodule MCPheonix.Resources.Registry do
  @moduledoc """
  Registry for Ash resources in the MCPheonix application.
  
  This module defines the resources that are available to the application
  and provides a centralized way to access them.
  """
  use Ash.Registry

  entries do
    # Register resource modules here
    entry MCPheonix.Resources.Message
    entry MCPheonix.Resources.User
  end
end 