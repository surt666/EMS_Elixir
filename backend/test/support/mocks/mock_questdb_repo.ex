defmodule EmsBackend.Test.Mocks.MockQuestDBRepo do
  @moduledoc """
  Mock implementation of QuestDBRepository for testing.
  Uses GenServer to maintain in-memory state during tests.
  """

  use GenServer

  @behaviour EmsBackend.Repositories.QuestDBRepository

  # Client API

  def start_link(_opts \\ []) do
    GenServer.start_link(__MODULE__, %{queries: [], inserts: []}, name: __MODULE__)
  end

  def reset do
    GenServer.call(__MODULE__, :reset)
  end

  def get_inserts do
    GenServer.call(__MODULE__, :get_inserts)
  end

  def get_queries do
    GenServer.call(__MODULE__, :get_queries)
  end

  @impl true
  def query(sql, params \\ []) do
    GenServer.call(__MODULE__, {:query, sql, params})
  end

  @impl true
  def insert(table, data) do
    GenServer.call(__MODULE__, {:insert, table, data})
  end

  @impl true
  def bulk_insert(table, data) do
    GenServer.call(__MODULE__, {:bulk_insert, table, data})
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    {:ok, %{queries: [], inserts: []}}
  end

  @impl true
  def handle_call(:reset, _from, _state) do
    {:reply, :ok, %{queries: [], inserts: []}}
  end

  @impl true
  def handle_call(:get_inserts, _from, state) do
    {:reply, state.inserts, state}
  end

  @impl true
  def handle_call(:get_queries, _from, state) do
    {:reply, state.queries, state}
  end

  @impl true
  def handle_call({:query, sql, params}, _from, state) do
    new_state = %{state | queries: [{sql, params} | state.queries]}
    # Return empty result for mock
    {:reply, {:ok, []}, new_state}
  end

  @impl true
  def handle_call({:insert, table, data}, _from, state) do
    new_state = %{state | inserts: [{table, data} | state.inserts]}
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call({:bulk_insert, table, data}, _from, state) do
    new_inserts = Enum.map(data, &{table, &1})
    new_state = %{state | inserts: new_inserts ++ state.inserts}
    {:reply, :ok, new_state}
  end
end
