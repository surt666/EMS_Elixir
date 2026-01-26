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

  # Browser scope for HTMX endpoints (will be added as needed)
  scope "/", EmsBackendWeb do
    pipe_through :browser
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
