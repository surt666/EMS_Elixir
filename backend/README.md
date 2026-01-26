# EMS Backend

Phoenix backend for the EMS (Energy Management System) application. This backend follows **Onion Architecture** with dependency injection for maximum testability.

## Architecture Overview

- **Frontend**: Astro.js application (separate, in `../frontend/`)
- **Backend**: Phoenix generates HTML fragments for HTMX requests
- **NO LiveView**: We only use HEEx templates for rendering HTML fragments
- **Data Storage**: Valkey/Redis (key-value) + QuestDB (time-series)

See [ARCHITECTURE.md](ARCHITECTURE.md) for detailed architecture documentation.

## Key Technologies

- **Phoenix Framework** - Web framework (controllers, routing)
- **HEEx Templates** - HTML templating for HTMX responses *(not LiveView)*
- **Redix** - Redis/Valkey client
- **Postgrex** - PostgreSQL wire protocol (for QuestDB queries)
- **Req** - HTTP client (for QuestDB REST API)

## Getting Started

### Prerequisites

- Elixir 1.20+
- Valkey or Redis running on localhost:6379
- QuestDB running on localhost:8812 (PostgreSQL), 9000 (HTTP), 9009 (ILP)

### Installation

```bash
# Install dependencies
mix deps.get

# Run tests (no external services needed!)
mix test

# Start the server
mix phx.server
```

The backend will be available at `http://localhost:4000`

## Project Structure

```
lib/ems_backend/
├── domain/              # Pure business logic (no dependencies)
│   ├── hierarchy_node.ex
│   └── user.ex
├── services/            # Orchestration layer (uses DI)
└── repositories/        # Infrastructure layer
    ├── valkey_repository.ex           # Behavior (interface)
    ├── valkey_repository_impl.ex      # Production impl
    ├── hierarchy_repository.ex        # Hexastore implementation
    └── questdb_repository_impl.ex

lib/ems_backend_web/
├── controllers/         # HTMX endpoint handlers
│   └── *_html/         # HEEx templates for HTML fragments
└── router.ex           # Route definitions

test/
├── ems_backend/        # Domain & service tests
│   ├── domain/
│   ├── services/
│   └── repositories/
└── support/mocks/      # Mock repositories for testing
```

## Testing

All tests run without external infrastructure:

```bash
# Run all tests
mix test

# Run specific test file
mix test test/ems_backend/domain/hierarchy_node_test.exs

# Run with coverage
mix test --cover
```

Tests use mock repositories (GenServer-based) instead of real Valkey/QuestDB.

## Development Philosophy

1. **Business logic in Domain layer** - Pure functions, no I/O
2. **Dependency Injection** - Services accept repository implementations
3. **Test without infrastructure** - Mocks enable fast, reliable tests
4. **HEEx for HTMX** - Templates generate HTML fragments, not full pages
5. **No LiveView** - Frontend handles all client-side interactivity

## Documentation

- [ARCHITECTURE.md](ARCHITECTURE.md) - Detailed architecture and patterns
- [AGENTS.md](AGENTS.md) - Agent system documentation
