# Monitoring & Observability Setup: Strategy UI (Feature 004)

**Feature**: Strategy Registration and Validation UI
**Date**: 2026-02-09
**Purpose**: Production monitoring, alerting, and performance dashboards

---

## Overview

This document provides comprehensive monitoring setup for Feature 004 using:
- **Phoenix LiveDashboard** (built-in, already available)
- **Telemetry** (instrumentation)
- **Prometheus + Grafana** (metrics collection and visualization)
- **Logger** (structured logging)

---

## 1. Phoenix LiveDashboard (Quick Setup)

### Already Configured

Phoenix LiveDashboard is already included in the project.

### Access

```
http://localhost:4000/dev/dashboard
```

### Key Metrics to Monitor

1. **Processes** tab:
   - LiveView processes count
   - Memory usage per process
   - Message queue length

2. **Metrics** tab:
   - HTTP request count
   - Request duration
   - LiveView mount time
   - Phoenix PubSub events

3. **ETS** tab:
   - Session storage
   - Cache usage

### Production Access Control

Add authentication to LiveDashboard in production:

```elixir
# lib/trading_strategy_web/router.ex
import TradingStrategyWeb.UserAuth

scope "/admin" do
  pipe_through [:browser, :require_authenticated_user, :require_admin_user]

  live_dashboard "/dashboard", metrics: TradingStrategyWeb.Telemetry
end

# Add admin check plug
defp require_admin_user(conn, _opts) do
  if conn.assigns.current_user.role == :admin do
    conn
  else
    conn
    |> put_flash(:error, "You must be an admin to access this page.")
    |> redirect(to: "/")
    |> halt()
  end
end
```

---

## 2. Telemetry Events (Feature 004 Specific)

### Already Implemented

Telemetry events are already in place for:

```elixir
[:trading_strategy, :strategies, :syntax_test, :start]
[:trading_strategy, :strategies, :syntax_test, :stop]
```

### Add Additional Events

**Update `lib/trading_strategy/strategies.ex`**:

```elixir
defmodule TradingStrategy.Strategies do
  # Add after create_strategy/2
  def create_strategy(attrs, user) do
    :telemetry.execute(
      [:trading_strategy, :strategies, :create, :start],
      %{system_time: System.system_time()},
      %{user_id: user.id}
    )

    start_time = System.monotonic_time()

    result = %Strategy{user_id: user.id}
    |> Strategy.changeset(attrs)
    |> Repo.insert()
    |> broadcast_strategy_change(:strategy_created, user.id)

    duration = System.monotonic_time() - start_time

    :telemetry.execute(
      [:trading_strategy, :strategies, :create, :stop],
      %{duration: duration},
      %{user_id: user.id, result: elem(result, 0)}
    )

    result
  end

  # Similar for update_strategy/3, activate_strategy/1, etc.
end
```

### Telemetry Metrics Definition

**Update `lib/trading_strategy_web/telemetry.ex`**:

```elixir
defmodule TradingStrategyWeb.Telemetry do
  use Supervisor
  import Telemetry.Metrics

  def start_link(arg) do
    Supervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end

  def init(_arg) do
    children = [
      {:telemetry_poller, measurements: periodic_measurements(), period: 10_000}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  def metrics do
    [
      # Phoenix Metrics (already included)
      summary("phoenix.endpoint.stop.duration",
        unit: {:native, :millisecond}
      ),
      summary("phoenix.router_dispatch.stop.duration",
        tags: [:route],
        unit: {:native, :millisecond}
      ),

      # LiveView Metrics
      summary("phoenix.live_view.mount.stop.duration",
        tags: [:view],
        unit: {:native, :millisecond}
      ),

      # Feature 004: Strategy Operations
      counter("trading_strategy.strategies.create.start",
        tags: [:user_id]
      ),
      summary("trading_strategy.strategies.create.stop.duration",
        tags: [:user_id, :result],
        unit: {:native, :millisecond}
      ),
      counter("trading_strategy.strategies.update.start",
        tags: [:user_id]
      ),
      summary("trading_strategy.strategies.update.stop.duration",
        tags: [:user_id, :result],
        unit: {:native, :millisecond}
      ),
      summary("trading_strategy.strategies.syntax_test.stop.duration",
        tags: [:format, :result],
        unit: {:native, :millisecond}
      ),

      # Database Metrics
      summary("trading_strategy.repo.query.total_time",
        unit: {:native, :millisecond}
      ),

      # VM Metrics
      summary("vm.memory.total", unit: {:byte, :megabyte}),
      summary("vm.total_run_queue_lengths.total"),
      summary("vm.total_run_queue_lengths.cpu"),
      summary("vm.total_run_queue_lengths.io")
    ]
  end

  defp periodic_measurements do
    []
  end
end
```

---

## 3. Prometheus + Grafana Setup

### Install Dependencies

**Add to `mix.exs`**:

```elixir
defp deps do
  [
    # Existing dependencies...
    {:telemetry_metrics_prometheus, "~> 1.1"},
    {:telemetry_poller, "~> 1.0"}
  ]
end
```

```bash
mix deps.get
```

### Configure Prometheus Exporter

**Create `lib/trading_strategy_web/telemetry/prometheus.ex`**:

```elixir
defmodule TradingStrategyWeb.Telemetry.Prometheus do
  use Supervisor
  require Logger

  def start_link(arg) do
    Supervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end

  @impl true
  def init(_arg) do
    children = [
      {
        TelemetryMetricsPrometheus,
        [
          metrics: TradingStrategyWeb.Telemetry.metrics(),
          port: 9568,
          name: :prometheus_metrics
        ]
      }
    ]

    Logger.info("Prometheus metrics available at http://localhost:9568/metrics")
    Supervisor.init(children, strategy: :one_for_one)
  end
end
```

**Add to supervision tree in `lib/trading_strategy/application.ex`**:

```elixir
def start(_type, _args) do
  children = [
    # Existing children...
    TradingStrategyWeb.Telemetry.Prometheus
  ]
  # ...
end
```

### Test Prometheus Endpoint

```bash
curl http://localhost:9568/metrics
```

Expected output:
```
# HELP phoenix_endpoint_stop_duration Phoenix endpoint stop duration
# TYPE phoenix_endpoint_stop_duration summary
phoenix_endpoint_stop_duration{quantile="0.5"} 123.456
...
```

---

## 4. Grafana Dashboard

### Install Grafana (Docker)

**Create `docker-compose.monitoring.yml`**:

```yaml
version: '3.8'

services:
  prometheus:
    image: prom/prometheus:latest
    ports:
      - "9090:9090"
    volumes:
      - ./monitoring/prometheus.yml:/etc/prometheus/prometheus.yml
      - prometheus_data:/prometheus
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'

  grafana:
    image: grafana/grafana:latest
    ports:
      - "3000:3000"
    volumes:
      - grafana_data:/var/lib/grafana
      - ./monitoring/grafana/dashboards:/etc/grafana/provisioning/dashboards
      - ./monitoring/grafana/datasources:/etc/grafana/provisioning/datasources
    environment:
      - GF_SECURITY_ADMIN_PASSWORD=admin
      - GF_USERS_ALLOW_SIGN_UP=false

volumes:
  prometheus_data:
  grafana_data:
```

### Prometheus Configuration

**Create `monitoring/prometheus.yml`**:

```yaml
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: 'trading-strategy'
    static_configs:
      - targets: ['host.docker.internal:9568']
        labels:
          app: 'trading-strategy'
          feature: '004-strategy-ui'
```

### Grafana Data Source

**Create `monitoring/grafana/datasources/prometheus.yml`**:

```yaml
apiVersion: 1

datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://prometheus:9090
    isDefault: true
```

### Grafana Dashboard JSON

**Create `monitoring/grafana/dashboards/dashboard.yml`**:

```yaml
apiVersion: 1

providers:
  - name: 'Strategy UI Dashboard'
    orgId: 1
    folder: ''
    type: file
    disableDeletion: false
    updateIntervalSeconds: 10
    options:
      path: /etc/grafana/provisioning/dashboards
```

**Create `monitoring/grafana/dashboards/strategy-ui-004.json`**:

```json
{
  "dashboard": {
    "title": "Strategy UI Performance (Feature 004)",
    "tags": ["feature-004", "strategy-ui"],
    "timezone": "browser",
    "panels": [
      {
        "id": 1,
        "title": "Strategy Creation Rate",
        "type": "graph",
        "targets": [
          {
            "expr": "rate(trading_strategy_strategies_create_start[5m])",
            "legendFormat": "Creations/sec"
          }
        ]
      },
      {
        "id": 2,
        "title": "Strategy Creation Duration (p95)",
        "type": "graph",
        "targets": [
          {
            "expr": "histogram_quantile(0.95, rate(trading_strategy_strategies_create_stop_duration_bucket[5m]))",
            "legendFormat": "p95 duration (ms)"
          }
        ]
      },
      {
        "id": 3,
        "title": "Validation Response Time",
        "type": "graph",
        "targets": [
          {
            "expr": "histogram_quantile(0.95, rate(phoenix_live_view_mount_stop_duration_bucket{view=\"StrategyLive.Form\"}[5m]))",
            "legendFormat": "p95 mount time (ms)"
          }
        ]
      },
      {
        "id": 4,
        "title": "Syntax Test Duration",
        "type": "graph",
        "targets": [
          {
            "expr": "histogram_quantile(0.95, rate(trading_strategy_strategies_syntax_test_stop_duration_bucket[5m]))",
            "legendFormat": "p95 syntax test (ms)"
          }
        ]
      },
      {
        "id": 5,
        "title": "HTTP Request Rate",
        "type": "graph",
        "targets": [
          {
            "expr": "rate(phoenix_endpoint_stop_duration_count[5m])",
            "legendFormat": "Requests/sec"
          }
        ]
      },
      {
        "id": 6,
        "title": "Error Rate",
        "type": "graph",
        "targets": [
          {
            "expr": "rate(trading_strategy_strategies_create_stop_duration_count{result=\"error\"}[5m])",
            "legendFormat": "Errors/sec"
          }
        ]
      },
      {
        "id": 7,
        "title": "Memory Usage",
        "type": "graph",
        "targets": [
          {
            "expr": "vm_memory_total",
            "legendFormat": "Total Memory (MB)"
          }
        ]
      }
    ]
  }
}
```

### Start Monitoring Stack

```bash
docker-compose -f docker-compose.monitoring.yml up -d
```

### Access Dashboards

- **Grafana**: http://localhost:3000 (admin/admin)
- **Prometheus**: http://localhost:9090

---

## 5. Alerting Rules

### Prometheus Alerts

**Create `monitoring/alerts.yml`**:

```yaml
groups:
  - name: strategy_ui_alerts
    interval: 30s
    rules:
      # High error rate
      - alert: HighStrategyCreationErrorRate
        expr: rate(trading_strategy_strategies_create_stop_duration_count{result="error"}[5m]) > 0.1
        for: 2m
        labels:
          severity: critical
          feature: "004-strategy-ui"
        annotations:
          summary: "High strategy creation error rate"
          description: "Error rate is {{ $value }} errors/sec (threshold: 0.1)"

      # Slow validation
      - alert: SlowValidationResponse
        expr: histogram_quantile(0.95, rate(phoenix_live_view_mount_stop_duration_bucket{view="StrategyLive.Form"}[5m])) > 1000
        for: 5m
        labels:
          severity: warning
          feature: "004-strategy-ui"
        annotations:
          summary: "Validation response time above 1 second (SC-002 violation)"
          description: "p95 validation time is {{ $value }}ms (threshold: 1000ms)"

      # Slow syntax test
      - alert: SlowSyntaxTest
        expr: histogram_quantile(0.95, rate(trading_strategy_strategies_syntax_test_stop_duration_bucket[5m])) > 3000
        for: 5m
        labels:
          severity: warning
          feature: "004-strategy-ui"
        annotations:
          summary: "Syntax test duration above 3 seconds (SC-005 violation)"
          description: "p95 syntax test time is {{ $value }}ms (threshold: 3000ms)"

      # High memory usage
      - alert: HighMemoryUsage
        expr: vm_memory_total > 2000
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High memory usage"
          description: "Memory usage is {{ $value }}MB (threshold: 2000MB)"

      # Database connection pool exhaustion
      - alert: DatabaseConnectionPoolNearExhaustion
        expr: sum(trading_strategy_repo_query_total_time_count) / 10 > 0.8
        for: 2m
        labels:
          severity: critical
        annotations:
          summary: "Database connection pool near exhaustion"
          description: "Pool usage is {{ $value }} (threshold: 0.8)"
```

### Add Alerts to Prometheus Config

**Update `monitoring/prometheus.yml`**:

```yaml
rule_files:
  - 'alerts.yml'

alerting:
  alertmanagers:
    - static_configs:
        - targets: ['alertmanager:9093']  # If using Alertmanager
```

---

## 6. Application Performance Monitoring (APM)

### Log-Based Monitoring

**Update `config/prod.exs`**:

```elixir
config :logger,
  level: :info,
  backends: [:console],
  compile_time_purge_matching: [
    [level_lower_than: :info]
  ]

config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id, :user_id, :strategy_id]
```

### Structured Logging for Strategy Operations

**Update `lib/trading_strategy/strategies.ex`**:

```elixir
require Logger

def create_strategy(attrs, user) do
  Logger.info("Strategy creation started",
    user_id: user.id,
    strategy_name: attrs["name"]
  )

  result = # ... creation logic ...

  case result do
    {:ok, strategy} ->
      Logger.info("Strategy created successfully",
        user_id: user.id,
        strategy_id: strategy.id,
        strategy_name: strategy.name
      )
    {:error, changeset} ->
      Logger.warning("Strategy creation failed",
        user_id: user.id,
        errors: inspect(changeset.errors)
      )
  end

  result
end
```

---

## 7. Health Checks

**Create `lib/trading_strategy_web/controllers/health_controller.ex`**:

```elixir
defmodule TradingStrategyWeb.HealthController do
  use TradingStrategyWeb, :controller

  def index(conn, _params) do
    status = %{
      status: "ok",
      timestamp: DateTime.utc_now(),
      checks: %{
        database: database_health(),
        memory: memory_health()
      }
    }

    json(conn, status)
  end

  defp database_health do
    case Ecto.Adapters.SQL.query(TradingStrategy.Repo, "SELECT 1") do
      {:ok, _} -> "ok"
      {:error, _} -> "error"
    end
  end

  defp memory_health do
    total = :erlang.memory(:total)
    limit = 2_000_000_000  # 2GB

    if total < limit do
      "ok"
    else
      "warning"
    end
  end
end
```

**Add route**:

```elixir
# lib/trading_strategy_web/router.ex
scope "/", TradingStrategyWeb do
  pipe_through :api

  get "/health", HealthController, :index
end
```

Test:
```bash
curl http://localhost:4000/health
```

---

## 8. Monitoring Checklist

### Pre-Production

- [ ] Telemetry metrics defined for all critical operations
- [ ] Prometheus exporter configured and accessible
- [ ] Grafana dashboards created for Feature 004
- [ ] Alert rules configured in Prometheus
- [ ] Health check endpoint working
- [ ] Structured logging implemented

### Production Deployment

- [ ] Prometheus scraping production metrics endpoint
- [ ] Grafana connected to production Prometheus
- [ ] Alert routing configured (email, Slack, PagerDuty)
- [ ] Log aggregation setup (ELK, Datadog, etc.)
- [ ] Dashboards accessible to ops team
- [ ] On-call rotation established

### Post-Deployment (Week 1)

- [ ] Baseline metrics captured
- [ ] Alert thresholds tuned based on real traffic
- [ ] False positive alerts reduced
- [ ] Dashboard refined based on team feedback
- [ ] Runbooks created for common alerts

---

## 9. Key Metrics Dashboard (Summary)

| Metric | Source | Target | Alert Threshold |
|--------|--------|--------|----------------|
| Strategy creation rate | Telemetry | Monitor | N/A |
| Strategy creation duration (p95) | Telemetry | <5000ms | >10000ms |
| Validation response time (p95) | LiveView | <1000ms | >1000ms (SC-002) |
| Syntax test duration (p95) | Telemetry | <3000ms | >3000ms (SC-005) |
| HTTP request rate | Phoenix | Monitor | N/A |
| Error rate | Telemetry | <1% | >5% |
| Memory usage | VM | <2GB | >2GB |
| Database query time (p95) | Ecto | <100ms | >500ms |

---

## 10. Maintenance

### Weekly

- [ ] Review alert history
- [ ] Check for new error patterns
- [ ] Verify dashboard accuracy

### Monthly

- [ ] Review and update alert thresholds
- [ ] Archive old metrics data
- [ ] Update dashboards based on usage

### Quarterly

- [ ] Audit monitoring coverage
- [ ] Review incident response times
- [ ] Update runbooks

---

**Setup Complete**: [ ] YES [ ] NO
**Verified By**: _______________ **Date**: ___________
