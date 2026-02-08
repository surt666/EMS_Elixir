# Hierarchy Data Generation

## Overview

This Elixir script generates sample hierarchy data in Valkey/Redis, matching the structure created by the Python script for DynamoDB.

## Usage

```bash
# Generate with default settings (10 buildings per property)
mix generate_hierarchy

# Generate with custom building count
mix generate_hierarchy --buildings-per-property 2
```

## What It Generates

### Hierarchy Structure
- **1 root node**
- **5 partners** under root
- **20 companies** per partner (100 total)
- **50 properties** per company (5,000 total)
- **N buildings** per property (configurable, default: 10)
  - With 10 buildings: 50,000 buildings
  - With 1 building: 5,000 buildings

### Additional Data
- **2 test users** with permissions:
  - `stel@energidata.dk` - Admin user with root access
  - `stel@enity.io` - Limited user with access to first company of partner 1
- **ID counters** for each node type (P, C, PR, B, S)
- **Parent-child relationships** using hexastore indexing
- **Descendant sets** for efficient queries

## Data Statistics

With 1 building per property:
- **Total nodes**: ~10,000
- **Total edges**: ~60,000 (6 indices per relationship)
- **Total items**: ~20,000 (nodes + user permissions + counters)

## Implementation Details

### Domain Integration
- Uses `EmsBackend.Domain.HierarchyNode` for node creation
- Uses `EmsBackend.Repositories.HierarchyValkeyImpl` for persistence
- Proper validation through domain layer

### Features
- **Retry logic** with exponential backoff for Redis operations
- **Progress indicators** during generation
- **ID counter management** in Redis
- **Proper metadata** for each node type:
  - Partners: email, address, phone
  - Companies: email, address, CVR, phone, contact, homepage, status, SLA
  - Properties: location (lat/long), address, usage, BBR, weather station
  - Buildings: email, location, usage, areas, BBR, build year, P-nr, external ID, weather station, timezone

### Error Handling
- Automatic retries on connection errors
- Exponential backoff (100ms, 200ms, 400ms)
- Detailed error messages

## Testing the Generated Data

### Query Redis Directly
```bash
# Count nodes
redis-cli KEYS "node:*" | wc -l

# Count edges
redis-cli KEYS "edge:*" | wc -l

# Check user permissions
redis-cli SMEMBERS "user_perms:stel@energidata.dk"
redis-cli SMEMBERS "user_perms:stel@enity.io"

# View descendant sets
redis-cli KEYS "descendants:*" | head -10
```

### Test via HTTP API
```bash
# Start the server
mix phx.server

# Query nodes for admin user (should return partners)
curl "http://localhost:4000/hierarchy/query/nodes?user=stel@energidata.dk"

# Query nodes for limited user (should return the one company they have access to)
curl "http://localhost:4000/hierarchy/query/nodes?user=stel@enity.io"

# Get children of a partner
curl "http://localhost:4000/hierarchy/query/nodes?id=P%231001&user=stel@energidata.dk"
```

## Clean Up

To remove all generated data:
```bash
redis-cli FLUSHDB
```

To regenerate with fresh data:
```bash
redis-cli FLUSHDB && mix generate_hierarchy --buildings-per-property 2
```

## Performance

Generation speed depends on Redis performance and the number of buildings per property:
- 1 building/property (~10K nodes): ~10-30 seconds
- 10 buildings/property (~50K nodes): ~60-120 seconds

The script uses retry logic to handle Redis connection issues during bulk operations.
