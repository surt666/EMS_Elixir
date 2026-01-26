# EMS Backend Architecture

This backend follows the **Onion Architecture** pattern with dependency injection for testability.

## Frontend Architecture

**Frontend:** Astro.js application (separate from this backend)
**Backend:** Phoenix generates HTML fragments for HTMX requests

### Phoenix Web Layer Role

- **NO LiveView** - We don't use any LiveView functionality
- **HEEx Templates Only** - Used to generate HTML fragments that services return to HTMX calls
- **Controllers** - Handle HTMX requests and return partial HTML responses
- **No Layouts** - No full page layouts, only HTML snippets

Example HTMX flow:
```elixir
# Controller returns HTML fragment via HEEx template
def show(conn, %{"id" => id}) do
  {:ok, node} = HierarchyService.get_node(id, valkey_repo())

  # Renders HEEx template as HTML fragment
  render(conn, "node.html", node: node)
end
```

The frontend (Astro.js) handles full page rendering, routing, and static assets. Phoenix only generates small HTML fragments for dynamic content updates via HTMX.

## Architecture Layers

```
┌─────────────────────────────────────────────┐
│        Frontend: Astro.js (separate)        │
│              ../frontend/                   │
│    - Full page rendering                    │
│    - Routing & static assets                │
│    - Makes HTMX requests to backend         │
└─────────────────────────────────────────────┘
                    ↓ HTMX
┌─────────────────────────────────────────────┐
│      Web Layer (Controllers + HEEx)         │
│         lib/ems_backend_web/                │
│    - Returns HTML fragments (not JSON)      │
│    - Uses HEEx for templating               │
└─────────────────────────────────────────────┘
                    ↓
┌─────────────────────────────────────────────┐
│        Application Layer (Services)         │
│         lib/ems_backend/services/           │
│    - Orchestrates business logic            │
│    - Uses dependency injection               │
└─────────────────────────────────────────────┘
                    ↓
┌─────────────────────────────────────────────┐
│         Domain Layer (Business Logic)       │
│         lib/ems_backend/domain/             │
│    - Pure business rules                    │
│    - No external dependencies               │
│    - Fully testable without infrastructure  │
└─────────────────────────────────────────────┘
                    ↑
┌─────────────────────────────────────────────┐
│      Infrastructure Layer (Repositories)    │
│       lib/ems_backend/repositories/         │
│    - ValkeyRepository (behavior)            │
│    - ValkeyRepositoryImpl                   │
│    - QuestDBRepository (behavior)           │
│    - QuestDBRepositoryImpl                  │
└─────────────────────────────────────────────┘
```

## Key Principles

### 1. Dependency Injection

Services accept repository implementations as parameters:

```elixir
# Production
EventService.create_event(attrs, ValkeyRepositoryImpl, QuestDBRepositoryImpl)

# Testing with mocks
EventService.create_event(attrs, MockValkeyRepo, MockQuestDBRepo)

# Testing with static functions
EventService.create_event(attrs, StaticCacheRepo, StaticTimeSeriesRepo)
```

### 2. Business Rules in Domain Layer

The domain layer contains pure business logic with no external dependencies:

```elixir
# Domain/Event.ex - Pure business logic
def publish(%Event{status: :draft} = event) do
  {:ok, %{event | status: :published}}
end

def can_register?(%Event{status: :published, capacity: capacity, registered_count: count}) do
  count < capacity
end
```

### 3. Repository Behaviors (Interfaces)

Define contracts that implementations must follow:

```elixir
# Repository behavior
defmodule ValkeyRepository do
  @callback get(key) :: {:ok, value} | {:error, term()}
  @callback set(key, value, ttl) :: :ok | {:error, term()}
end

# Production implementation
defmodule ValkeyRepositoryImpl do
  @behaviour ValkeyRepository

  def get(key), do: Redix.command(:redix, ["GET", key])
  def set(key, value, ttl), do: Redix.command(:redix, ["SET", key, value])
end

# Mock implementation
defmodule MockValkeyRepo do
  @behaviour ValkeyRepository

  def get(key), do: Agent.get(__MODULE__, &Map.get(&1, key))
  def set(key, value, _), do: Agent.update(__MODULE__, &Map.put(&1, key, value))
end
```

## HEEx Templates for HTMX Responses

We use Phoenix's HEEx (HTML + EEx) templating engine **only** to generate HTML fragments for HTMX responses. We do **NOT** use LiveView.

### Template Structure

Templates are placed in controller-specific directories:
```
lib/ems_backend_web/controllers/
  hierarchy_html/
    node.html.heex      # Renders a single node
    children.html.heex  # Renders list of children
```

### Example Template

```heex
<%# hierarchy_html/node.html.heex %>
<div id={"node-#{@node.id}"} class="hierarchy-node">
  <h3><%= @node.name %></h3>
  <p>Type: <%= @node.type %></p>
  <p>Status: <%= if @node.blocked, do: "Blocked", else: "Active" %></p>
</div>
```

### Why HEEx Instead of JSON?

HTMX expects HTML responses, not JSON. The service layer orchestrates business logic, then the controller uses a HEEx template to format the response as HTML:

```elixir
# Service returns domain model
{:ok, node} = HierarchyService.get_node(id, valkey_repo)

# Controller renders as HTML fragment using HEEx
render(conn, "node.html", node: node)
```

**Note:** We keep `phoenix_live_view` as a dependency solely for the HEEx templating engine. We don't use any LiveView features (live sockets, pubsub, etc.).

## Repositories

### Valkey Repository

Provides key-value storage interface with Redis/Valkey backend.

**Operations:**
- `get(key)` - Retrieve value
- `set(key, value, ttl)` - Store value with optional TTL
- `delete(key)` - Remove key
- `exists?(key)` - Check if key exists
- `keys(pattern)` - Find keys matching pattern

### QuestDB Repository

Provides time-series database interface with multiple protocols:

1. **PostgreSQL Wire Protocol** (via Postgrex)
   - Port: 8812
   - Use for: SQL queries

2. **HTTP REST API** (via Req)
   - Port: 9000
   - Use for: Single inserts, flexible operations

3. **InfluxDB Line Protocol** (via :gen_tcp)
   - Port: 9009
   - Use for: High-performance bulk inserts

**Operations:**
- `query(sql, params)` - Execute SQL queries (uses Postgrex)
- `insert(table, data)` - Single insert (uses HTTP)
- `bulk_insert(table, data)` - Bulk insert (uses ILP)

## Testing Without Infrastructure

Tests run without Redis, Valkey, or QuestDB:

```bash
# Run tests - no external services needed!
mix test
```

### Domain Tests

Test pure business logic in isolation:

```elixir
test "cannot publish an already published event" do
  {:ok, event} = Event.new(valid_attrs())
  {:ok, published} = Event.publish(event)

  assert {:error, _} = Event.publish(published)
end
```

### Service Tests with Mocks

Test service orchestration with mock repositories:

```elixir
test "creates event using injected repositories" do
  {:ok, event} = EventService.create_event(
    attrs,
    MockValkeyRepo,      # No real Valkey needed
    MockQuestDBRepo      # No real QuestDB needed
  )

  # Verify business logic
  assert event.status == :draft

  # Verify repository interactions
  assert {:ok, _} = MockValkeyRepo.get("event:#{event.id}")
  assert [{"event_logs", log_data}] = MockQuestDBRepo.get_inserts()
end
```

## Configuration

### Development/Production

```elixir
# config/config.exs
config :ems_backend,
  valkey_repo: EmsBackend.Repositories.ValkeyRepositoryImpl,
  questdb_repo: EmsBackend.Repositories.QuestDBRepositoryImpl
```

### Testing

```elixir
# config/test.exs
config :ems_backend,
  valkey_repo: EmsBackend.Test.Mocks.MockValkeyRepo,
  questdb_repo: EmsBackend.Test.Mocks.MockQuestDBRepo
```

## Environment Variables

### Valkey/Redis
- `REDIS_HOST` - Default: localhost
- `REDIS_PORT` - Default: 6379

### QuestDB
- `QUESTDB_PG_HOST` - PostgreSQL wire protocol host (default: localhost)
- `QUESTDB_PG_PORT` - PostgreSQL wire protocol port (default: 8812)
- `QUESTDB_HTTP_HOST` - HTTP API host (default: localhost)
- `QUESTDB_HTTP_PORT` - HTTP API port (default: 9000)
- `QUESTDB_ILP_HOST` - InfluxDB Line Protocol host (default: localhost)
- `QUESTDB_ILP_PORT` - InfluxDB Line Protocol port (default: 9009)

## Example: Adding a New Feature

1. **Define domain logic** in `lib/ems_backend/domain/`:
   ```elixir
   defmodule Domain.Registration do
     def validate_email(email), do: # pure logic
   end
   ```

2. **Create service** in `lib/ems_backend/services/`:
   ```elixir
   defmodule Services.RegistrationService do
     def register_user(attrs, cache_repo, db_repo) do
       # Orchestrate domain logic and repositories
     end
   end
   ```

3. **Write tests** in `test/`:
   ```elixir
   test "registers user with valid email" do
     RegistrationService.register_user(
       attrs,
       MockValkeyRepo,
       MockQuestDBRepo
     )
   end
   ```

4. **Create controller** in `lib/ems_backend_web/controllers/`:
   ```elixir
   def create(conn, params) do
     cache = RepoConfig.valkey_repo()
     db = RepoConfig.questdb_repo()
     RegistrationService.register_user(params, cache, db)
   end
   ```

## Benefits

✅ **Testable** - Business logic tested without infrastructure
✅ **Flexible** - Easy to swap implementations
✅ **Maintainable** - Clear separation of concerns
✅ **Fast Tests** - No database setup needed
✅ **Type Safe** - Behaviors ensure interface compliance
