# Deployment Guide

Production deployment guide for the Trading Strategy DSL Library.

## Prerequisites

- Linux server (Ubuntu 20.04+ recommended)
- Elixir 1.17+ (OTP 27+)
- PostgreSQL 14+ with TimescaleDB extension
- Redis 6+ (for distributed rate limiting)
- Domain name with SSL certificate

## Local Development

### Using Docker Compose

```bash
# Start all services
docker-compose up -d

# Check status
docker-compose ps

# View logs
docker-compose logs -f trading_strategy

# Stop services
docker-compose down
```

## Production Deployment

### 1. Server Setup

```bash
# Update system
sudo apt update && sudo apt upgrade -y

# Install Erlang and Elixir
wget https://packages.erlang-solutions.com/erlang-solutions_2.0_all.deb
sudo dpkg -i erlang-solutions_2.0_all.deb
sudo apt update
sudo apt install -y esl-erlang elixir

# Install PostgreSQL + TimescaleDB
sudo apt install -y postgresql-14 postgresql-contrib
sudo add-apt-repository ppa:timescale/timescaledb-ppa
sudo apt update
sudo apt install -y timescaledb-2-postgresql-14

# Install Redis
sudo apt install -y redis-server
sudo systemctl enable redis-server

# Install Nginx
sudo apt install -y nginx
sudo systemctl enable nginx
```

### 2. Database Setup

```bash
# Create database user
sudo -u postgres createuser trading_strategy -P

# Create database
sudo -u postgres createdb trading_strategy_prod -O trading_strategy

# Enable TimescaleDB
sudo -u postgres psql -d trading_strategy_prod -c "CREATE EXTENSION IF NOT EXISTS timescaledb;"

# Tune TimescaleDB
sudo timescaledb-tune --quiet --yes
sudo systemctl restart postgresql
```

### 3. Application Deployment

```bash
# Clone repository
git clone https://github.com/rzcastilho/trading-strategy.git
cd trading-strategy

# Install dependencies
mix deps.get --only prod

# Compile assets (if using LiveView dashboard)
mix assets.deploy

# Compile application
MIX_ENV=prod mix compile

# Run migrations
MIX_ENV=prod mix ecto.migrate

# Build release
MIX_ENV=prod mix release
```

### 4. Environment Configuration

Create `/etc/trading_strategy/prod.secret.exs`:

```elixir
import Config

config :trading_strategy, TradingStrategy.Repo,
  username: System.get_env("DATABASE_USER") || "trading_strategy",
  password: System.fetch_env!("DATABASE_PASSWORD"),
  hostname: System.get_env("DATABASE_HOST") || "localhost",
  database: "trading_strategy_prod",
  pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10")

config :trading_strategy, TradingStrategyWeb.Endpoint,
  secret_key_base: System.fetch_env!("SECRET_KEY_BASE"),
  http: [port: String.to_integer(System.get_env("PORT") || "4000")],
  url: [host: System.fetch_env!("HOST"), port: 443, scheme: "https"]

config :hammer,
  backend: {Hammer.Backend.Redis,
    redis_url: System.get_env("REDIS_URL") || "redis://localhost:6379/1",
    pool_size: 4
  }
```

Set environment variables:

```bash
export DATABASE_PASSWORD="secure_password"
export SECRET_KEY_BASE="$(mix phx.gen.secret)"
export HOST="trading.yourdomain.com"
export PORT="4000"
export REDIS_URL="redis://localhost:6379/1"
```

### 5. Systemd Service

Create `/etc/systemd/system/trading_strategy.service`:

```ini
[Unit]
Description=Trading Strategy Application
After=network.target postgresql.service redis.service

[Service]
Type=simple
User=trading_strategy
Group=trading_strategy
WorkingDirectory=/home/trading_strategy/trading-strategy
Environment="MIX_ENV=prod"
Environment="PHX_SERVER=true"
Environment="RELEASE_COOKIE=your_secure_cookie_here"
EnvironmentFile=/etc/trading_strategy/env
ExecStart=/home/trading_strategy/trading-strategy/_build/prod/rel/trading_strategy/bin/trading_strategy start
ExecStop=/home/trading_strategy/trading-strategy/_build/prod/rel/trading_strategy/bin/trading_strategy stop
Restart=on-failure
RestartSec=5
SyslogIdentifier=trading_strategy
RemainAfterExit=no

[Install]
WantedBy=multi-user.target
```

Create `/etc/trading_strategy/env`:

```bash
DATABASE_PASSWORD=secure_password
SECRET_KEY_BASE=generated_secret_key_base
HOST=trading.yourdomain.com
PORT=4000
REDIS_URL=redis://localhost:6379/1
```

Enable and start service:

```bash
sudo systemctl daemon-reload
sudo systemctl enable trading_strategy
sudo systemctl start trading_strategy
sudo systemctl status trading_strategy
```

### 6. Nginx Configuration

Create `/etc/nginx/sites-available/trading_strategy`:

```nginx
upstream phoenix {
    server 127.0.0.1:4000;
}

map $http_upgrade $connection_upgrade {
    default upgrade;
    '' close;
}

server {
    listen 80;
    server_name trading.yourdomain.com;
    return 301 https://$server_name$request_uri;
}

server {
    listen 443 ssl http2;
    server_name trading.yourdomain.com;

    ssl_certificate /etc/letsencrypt/live/trading.yourdomain.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/trading.yourdomain.com/privkey.pem;

    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers on;

    location / {
        proxy_pass http://phoenix;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection $connection_upgrade;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }

    location /api/live_trading {
        proxy_pass http://phoenix;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;

        # Longer timeout for live trading endpoints
        proxy_connect_timeout 300s;
        proxy_send_timeout 300s;
        proxy_read_timeout 300s;
    }
}
```

Enable site:

```bash
sudo ln -s /etc/nginx/sites-available/trading_strategy /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl reload nginx
```

### 7. SSL Certificate (Let's Encrypt)

```bash
sudo apt install -y certbot python3-certbot-nginx
sudo certbot --nginx -d trading.yourdomain.com
sudo systemctl reload nginx
```

## Monitoring

### Health Checks

```bash
# Application health
curl https://trading.yourdomain.com/api/health

# Database health
sudo -u postgres psql -d trading_strategy_prod -c "SELECT 1;"

# Redis health
redis-cli ping
```

### Logs

```bash
# Application logs
sudo journalctl -u trading_strategy -f

# Nginx logs
sudo tail -f /var/log/nginx/access.log
sudo tail -f /var/log/nginx/error.log

# PostgreSQL logs
sudo tail -f /var/log/postgresql/postgresql-14-main.log
```

### Telemetry

Integrate with monitoring services:

```elixir
# config/prod.exs
config :trading_strategy, TradingStrategy.Telemetry,
  metrics_reporter: TradingStrategy.Telemetry.PrometheusReporter,
  prometheus_port: 9568
```

## Backup Strategy

### Database Backups

```bash
# Daily automated backup
sudo -u postgres pg_dump trading_strategy_prod | gzip > /backups/trading_strategy_$(date +%Y%m%d).sql.gz

# Restore from backup
gunzip < /backups/trading_strategy_20250101.sql.gz | sudo -u postgres psql trading_strategy_prod
```

### Cron Job

```bash
sudo crontab -e

# Add daily backup at 2 AM
0 2 * * * /usr/bin/pg_dump -U postgres trading_strategy_prod | gzip > /backups/trading_strategy_$(date +\%Y\%m\%d).sql.gz
```

## Security Checklist

- [ ] Firewall configured (UFW/iptables)
- [ ] SSL certificate installed and auto-renewal enabled
- [ ] Database credentials rotated
- [ ] Secret key base generated uniquely
- [ ] Redis password set (if exposed)
- [ ] Rate limiting configured
- [ ] API authentication enabled
- [ ] Sensitive logs filtered
- [ ] Regular security updates scheduled

## Scaling

### Horizontal Scaling

Multiple application nodes with distributed session state:

```elixir
# config/prod.exs
config :trading_strategy,
  distributed_nodes: ["node1@10.0.0.1", "node2@10.0.0.2"],
  session_backend: :redis  # Shared session state
```

### Database Optimization

```sql
-- Hypertable partitioning
SELECT create_hypertable('market_data', 'timestamp', chunk_time_interval => INTERVAL '1 week');

-- Compression policy
SELECT add_compression_policy('market_data', INTERVAL '30 days');

-- Retention policy (delete old data)
SELECT add_retention_policy('market_data', INTERVAL '2 years');

-- Continuous aggregates for fast queries
CREATE MATERIALIZED VIEW market_data_1d
WITH (timescaledb.continuous) AS
SELECT time_bucket('1 day', timestamp) AS bucket,
       symbol,
       first(open, timestamp) AS open,
       max(high) AS high,
       min(low) AS low,
       last(close, timestamp) AS close,
       sum(volume) AS volume
FROM market_data
GROUP BY bucket, symbol;

SELECT add_continuous_aggregate_policy('market_data_1d',
  start_offset => INTERVAL '3 days',
  end_offset => INTERVAL '1 hour',
  schedule_interval => INTERVAL '1 hour');
```

## Troubleshooting

### Application Won't Start

```bash
# Check logs
sudo journalctl -u trading_strategy -n 100 --no-pager

# Check database connection
MIX_ENV=prod mix run -e "TradingStrategy.Repo.query!(\"SELECT 1\")"

# Check port availability
sudo netstat -tlnp | grep 4000
```

### High Memory Usage

```bash
# Check process memory
ps aux | grep beam.smp

# Reduce pool size in config
# config/prod.exs: pool_size: 5 (instead of 10)
```

### Database Performance

```bash
# Check slow queries
sudo -u postgres psql trading_strategy_prod -c "
SELECT query, mean_exec_time, calls
FROM pg_stat_statements
ORDER BY mean_exec_time DESC
LIMIT 10;"

# Analyze table statistics
sudo -u postgres psql trading_strategy_prod -c "ANALYZE;"
```

## Updates and Maintenance

```bash
# Pull latest code
cd /home/trading_strategy/trading-strategy
git pull origin main

# Run migrations
MIX_ENV=prod mix ecto.migrate

# Rebuild release
MIX_ENV=prod mix release --overwrite

# Restart service
sudo systemctl restart trading_strategy
```

## Disaster Recovery

1. Restore database from backup
2. Restore application code from git
3. Restore environment configuration from `/etc/trading_strategy/`
4. Rebuild and restart application

## Support

- Health check endpoint: `/api/health`
- Metrics endpoint: `/metrics` (if Prometheus enabled)
- Application logs: `journalctl -u trading_strategy`
