defmodule EmsBackend.Repositories.QuestDBRepository do
  @moduledoc """
  Behavior for QuestDB time-series database repositories.
  This defines the port/interface that repository adapters must implement.
  """

  @type query :: String.t()
  @type params :: list()
  @type result :: list(map())

  @callback query(query, params) :: {:ok, result} | {:error, term()}
  @callback insert(table :: String.t(), data :: map()) :: :ok | {:error, term()}
  @callback bulk_insert(table :: String.t(), data :: [map()]) :: :ok | {:error, term()}
end
