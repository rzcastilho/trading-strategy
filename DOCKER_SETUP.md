# Docker Setup for Local Development

## Prerequisites

- Docker and Docker Compose installed
- Ports 5432 and 5433 available

## Quick Start

### 1. Start PostgreSQL with TimescaleDB

```bash
docker-compose up -d
```

This starts two PostgreSQL instances:
- **Development DB**: Port 5432 (database: `trading_strategy_dev`)
- **Test DB**: Port 5433 (database: `trading_strategy_test`)

Both instances include the TimescaleDB extension for time-series data.

### 2. Verify Containers are Running

```bash
docker-compose ps
```

You should see both `trading_strategy_db` and `trading_strategy_test_db` running.

### 3. Create and Migrate Database

```bash
# Create the database
mix ecto.create

# Run migrations (once you have migrations)
mix ecto.migrate
```

### 4. Check Database Connection

```bash
# Connect to development database
docker exec -it trading_strategy_db psql -U postgres -d trading_strategy_dev

# Check TimescaleDB extension
\dx

# Exit psql
\q
```

## Database Configuration

### Development (port 5432)
- **Host**: localhost
- **Port**: 5432
- **Database**: trading_strategy_dev
- **Username**: postgres
- **Password**: postgres

### Test (port 5433)
- **Host**: localhost
- **Port**: 5433
- **Database**: trading_strategy_test
- **Username**: postgres
- **Password**: postgres

## Useful Commands

### Stop Containers
```bash
docker-compose stop
```

### Start Existing Containers
```bash
docker-compose start
```

### Restart Containers
```bash
docker-compose restart
```

### Stop and Remove Containers
```bash
docker-compose down
```

### Stop and Remove Containers + Volumes (deletes all data!)
```bash
docker-compose down -v
```

### View Logs
```bash
# All services
docker-compose logs -f

# Specific service
docker-compose logs -f postgres
```

### Access PostgreSQL CLI
```bash
# Development database
docker exec -it trading_strategy_db psql -U postgres -d trading_strategy_dev

# Test database
docker exec -it trading_strategy_test_db psql -U postgres -d trading_strategy_test
```

## Troubleshooting

### Port Already in Use
If ports 5432 or 5433 are already in use, you can either:
1. Stop the conflicting service
2. Change the port mapping in `docker-compose.yml`

### Database Connection Refused
1. Ensure containers are running: `docker-compose ps`
2. Check container logs: `docker-compose logs postgres`
3. Verify health check: `docker inspect trading_strategy_db`

### Reset Database
```bash
# Stop containers and remove volumes
docker-compose down -v

# Start fresh
docker-compose up -d

# Recreate database
mix ecto.create
mix ecto.migrate
```
