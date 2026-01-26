# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :ems_backend,
  generators: [timestamp_type: :utc_datetime, binary_id: true],
  redis_host: "localhost",
  redis_port: 6379,
  questdb_pg_host: "localhost",
  questdb_pg_port: 8812,
  questdb_http_host: "localhost",
  questdb_http_port: 9000,
  questdb_ilp_host: "localhost",
  questdb_ilp_port: 9009

# Configure the endpoint
config :ems_backend, EmsBackendWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: EmsBackendWeb.ErrorHTML, json: EmsBackendWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: EmsBackend.PubSub

# Configure the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :ems_backend, EmsBackend.Mailer, adapter: Swoosh.Adapters.Local

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
