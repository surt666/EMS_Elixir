# EMS - Event Management System

A full-stack Event Management System built with Elixir Phoenix and Astro.

## Project Structure

- `backend/` - Phoenix backend with HTML template support and Redis/Valkey integration
- `frontend/` - Astro frontend application

## Backend

The backend is built with Elixir Phoenix and includes:

- HTML template rendering with Phoenix templates
- Redis/Valkey support via Redix driver
- CORS configuration for frontend integration
- RESTful API endpoints

### Setup

```bash
cd backend
mix deps.get
mix phx.server
```

The backend will run on http://localhost:4000

### Environment Variables

- `REDIS_HOST` - Redis/Valkey host (default: localhost)
- `REDIS_PORT` - Redis/Valkey port (default: 6379)
- `PORT` - Phoenix server port (default: 4000)

## Frontend

The frontend is built with Astro.

### Setup

```bash
cd frontend
npm install
npm run dev
```

The frontend will run on http://localhost:4321

## Development

1. Start Redis/Valkey:
   ```bash
   redis-server
   # or for Valkey:
   valkey-server
   ```

2. Start the backend:
   ```bash
   cd backend
   mix phx.server
   ```

3. Start the frontend:
   ```bash
   cd frontend
   npm run dev
   ```

## Redis/Valkey Usage

The backend includes a configured Redix connection that can be used throughout the application:

```elixir
# Example usage
{:ok, value} = Redix.command(:redix, ["GET", "key"])
{:ok, "OK"} = Redix.command(:redix, ["SET", "key", "value"])
```

## CORS

The backend is configured to accept requests from:
- http://localhost:4321 (Astro dev server)
- http://localhost:3000 (Alternative frontend port)
- *.amplifyapp.com (AWS Amplify deployments)
