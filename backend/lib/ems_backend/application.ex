defmodule EmsBackend.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      EmsBackendWeb.Telemetry,
      {DNSCluster, query: Application.get_env(:ems_backend, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: EmsBackend.PubSub},
      # Redis/Valkey connection
      {Redix, name: :redix, host: redis_host(), port: redis_port()},
      # QuestDB connection (PostgreSQL wire protocol)
      # {Postgrex, name: :questdb, hostname: questdb_pg_host(), port: questdb_pg_port(), database: "qdb", username: "admin", password: "quest"},
      # Start a worker by calling: EmsBackend.Worker.start_link(arg)
      # {EmsBackend.Worker, arg},
      # Start to serve requests, typically the last entry
      EmsBackendWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: EmsBackend.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    EmsBackendWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp redis_host do
    System.get_env("REDIS_HOST") || Application.get_env(:ems_backend, :redis_host) || "localhost"
  end

  defp redis_port do
    case System.get_env("REDIS_PORT") do
      nil -> Application.get_env(:ems_backend, :redis_port) || 6379
      port -> String.to_integer(port)
    end
  end

  # defp questdb_pg_host do
  #   System.get_env("QUESTDB_PG_HOST") || Application.get_env(:ems_backend, :questdb_pg_host) || "localhost"
  # end

  # defp questdb_pg_port do
  #   case System.get_env("QUESTDB_PG_PORT") do
  #     nil -> Application.get_env(:ems_backend, :questdb_pg_port) || 8812
  #     port -> String.to_integer(port)
  #   end
  # end
end
