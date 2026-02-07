defmodule EmsBackendWeb.Router do
  use EmsBackendWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_flash
    # No layout needed - only generating HTML fragments for HTMX
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  # HTMX pipeline - no CSRF protection for HTMX requests
  pipeline :htmx do
    plug :accepts, ["html", "json"]
    plug :fetch_session
  end

  # Browser scope for HTMX endpoints (will be added as needed)
  scope "/", EmsBackendWeb do
    pipe_through :browser
  end

  # Hierarchy endpoints for HTMX
  scope "/hierarchy", EmsBackendWeb do
    pipe_through :htmx

    # Query endpoints (GET)
    get "/query/nodes", HierarchyController, :query_nodes
    get "/query/node", HierarchyController, :query_node
    get "/query/sensors", HierarchyController, :query_sensors
    get "/query/timezones", HierarchyController, :query_timezones
    get "/query/profiles", HierarchyController, :query_profiles
    get "/query/languages", HierarchyController, :query_languages
    get "/query/currencies", HierarchyController, :query_currencies
    get "/query/permissions", HierarchyController, :query_permissions
    get "/query/nodetypes", HierarchyController, :query_nodetypes
    get "/query/users", HierarchyController, :query_users

    # Command endpoint (POST)
    post "/command", HierarchyController, :command

    # CORS preflight
    options "/query/nodes", HierarchyController, :options
    options "/query/node", HierarchyController, :options
    options "/query/sensors", HierarchyController, :options
    options "/command", HierarchyController, :options
  end

  # API routes with dependency injection pattern
  scope "/api", EmsBackendWeb do
    pipe_through :api

    # API endpoints will be added here as needed
  end

  # Enable Swoosh mailbox preview in development
  if Application.compile_env(:ems_backend, :dev_routes) do
    scope "/dev" do
      pipe_through :browser

      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
