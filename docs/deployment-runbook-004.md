# Deployment Runbook: Strategy UI (Feature 004)

**Feature**: Strategy Registration and Validation UI
**Date**: 2026-02-09
**Version**: 1.0

## Pre-Deployment Checklist

- [ ] All Phase 1-8 tasks completed and tested
- [ ] Database migrations reviewed and tested in staging
- [ ] Authentication system configured (mailer, session secret)
- [ ] Environment variables set for production
- [ ] Backup of production database taken
- [ ] Rollback plan documented and tested

## Environment Variables

Ensure these are set in production:

```bash
# Application
PHX_HOST=your-domain.com
PORT=4000
SECRET_KEY_BASE=<generate with: mix phx.gen.secret>

# Database
DATABASE_URL=postgresql://user:password@host:5432/trading_strategy_prod
POOL_SIZE=10

# Authentication
# Generate with: mix phx.gen.secret
LIVE_VIEW_SIGNING_SALT=<secret>

# Mailer (for password resets, confirmations)
SMTP_HOST=smtp.sendgrid.net
SMTP_PORT=587
SMTP_USERNAME=apikey
SMTP_PASSWORD=<your-sendgrid-api-key>
MAILER_FROM_EMAIL=noreply@your-domain.com
MAILER_FROM_NAME="Trading Strategy Platform"

# Optional: Feature flags
MAX_CONCURRENT_BACKTESTS=5
STRATEGY_AUTOSAVE_INTERVAL_MS=30000
```

## Deployment Steps

### Step 1: Pre-Deployment Verification (Staging)

1. Deploy to staging environment first:
```bash
# On staging server
git checkout 004-strategy-ui
git pull origin 004-strategy-ui
MIX_ENV=staging mix deps.get --only prod
MIX_ENV=staging mix compile
```

2. Run migrations in staging:
```bash
MIX_ENV=staging mix ecto.migrate
```

3. Verify migrations succeeded:
```bash
MIX_ENV=staging mix ecto.migrations
# Should show all migrations as "up"
```

4. Start staging server:
```bash
MIX_ENV=staging mix phx.server
```

5. Test critical flows:
- [ ] User registration works
- [ ] User login works
- [ ] Strategy creation works
- [ ] Strategy edit with version conflict detection works
- [ ] Strategy activation blocked without backtest
- [ ] User isolation (users can't see each other's strategies)

### Step 2: Database Backup

```bash
# On production database server
pg_dump -U postgres -d trading_strategy_prod -F c -f backup_before_004_$(date +%Y%m%d_%H%M%S).dump
```

Store backup in secure location with 30-day retention.

### Step 3: Production Deployment

1. SSH into production server:
```bash
ssh production-server
cd /opt/trading_strategy
```

2. Pull latest code:
```bash
git fetch origin
git checkout 004-strategy-ui
git pull origin 004-strategy-ui
```

3. Build release:
```bash
MIX_ENV=prod mix deps.get --only prod
MIX_ENV=prod mix compile
MIX_ENV=prod mix assets.deploy  # If using assets
MIX_ENV=prod mix release
```

4. Stop current application:
```bash
sudo systemctl stop trading_strategy
```

5. Run migrations:
```bash
_build/prod/rel/trading_strategy/bin/trading_strategy eval "TradingStrategy.Release.migrate"
```

6. Start application:
```bash
sudo systemctl start trading_strategy
```

7. Verify service status:
```bash
sudo systemctl status trading_strategy
journalctl -u trading_strategy -f  # Watch logs
```

### Step 4: Post-Deployment Verification

1. Health check:
```bash
curl https://your-domain.com/health
# Expected: {"status": "ok"}
```

2. Test authentication:
- Visit `https://your-domain.com/users/register`
- Register a test user
- Login successfully

3. Test strategy creation:
- Navigate to `/strategies/new`
- Create a test strategy
- Verify real-time validation works
- Test syntax validation

4. Test version conflict:
- Open same strategy in two browser windows
- Save from one window
- Try to save from second window
- Verify conflict detection message

5. Monitor error logs:
```bash
tail -f /var/log/trading_strategy/prod.log
# Watch for any errors or warnings
```

### Step 5: Smoke Tests

Run these critical user flows:

```bash
# Test 1: User Registration and Login
curl -X POST https://your-domain.com/users/register \
  -d "user[email]=test@example.com&user[password]=securepass123"

# Test 2: Strategy Creation (requires auth)
# Use browser or authenticated curl with session cookie

# Test 3: Strategy List
# Visit https://your-domain.com/strategies
# Verify list loads in <2 seconds
```

## Rollback Plan

If critical issues are detected:

### Option 1: Rollback Code (Recommended)

```bash
# Stop application
sudo systemctl stop trading_strategy

# Revert to previous release
git checkout main  # or previous stable branch
MIX_ENV=prod mix compile
MIX_ENV=prod mix release

# Rollback migrations
_build/prod/rel/trading_strategy/bin/trading_strategy eval "TradingStrategy.Release.rollback(1)"

# Start application
sudo systemctl start trading_strategy
```

### Option 2: Restore Database (Last Resort)

```bash
# Stop application
sudo systemctl stop trading_strategy

# Restore database from backup
pg_restore -U postgres -d trading_strategy_prod -c backup_before_004_YYYYMMDD_HHMMSS.dump

# Revert code to previous version
git checkout main
MIX_ENV=prod mix release

# Start application
sudo systemctl start trading_strategy
```

## Monitoring and Alerts

### Key Metrics to Watch

1. **Application Metrics**:
   - HTTP 500 error rate (should be <0.1%)
   - Average response time (should be <500ms)
   - Database connection pool utilization (should be <80%)

2. **Strategy Operations**:
   - Strategy creation success rate
   - Validation response time (<1s per SC-002)
   - Syntax test duration (<3s per SC-005)

3. **Authentication**:
   - Login success rate
   - Session expiration errors
   - Password reset success rate

### Alert Thresholds

Set up alerts for:
- HTTP 5xx errors > 10/minute
- Database connection failures
- Average response time > 2 seconds
- Memory usage > 80%
- CPU usage > 90% for 5+ minutes

### Dashboard Queries

```sql
-- Check user registrations
SELECT COUNT(*) FROM users WHERE inserted_at > NOW() - INTERVAL '1 day';

-- Check strategy creation rate
SELECT COUNT(*) FROM strategies WHERE inserted_at > NOW() - INTERVAL '1 day';

-- Check version conflicts
SELECT COUNT(*) FROM strategies WHERE lock_version > 1;

-- Check active vs draft strategies
SELECT status, COUNT(*) FROM strategies GROUP BY status;
```

## Troubleshooting

### Issue: "user_id can't be blank" errors

**Cause**: Migration not applied or existing strategies without user_id

**Fix**:
```bash
# Verify migration status
MIX_ENV=prod mix ecto.migrations

# If missing, run migrations
_build/prod/rel/trading_strategy/bin/trading_strategy eval "TradingStrategy.Release.migrate"
```

### Issue: Authentication not working

**Cause**: Missing or incorrect SECRET_KEY_BASE

**Fix**:
```bash
# Generate new secret
mix phx.gen.secret

# Update environment variable
export SECRET_KEY_BASE=<generated-secret>

# Restart application
sudo systemctl restart trading_strategy
```

### Issue: Slow strategy list loading

**Cause**: Missing database indexes

**Fix**:
```sql
-- Verify indexes exist
\d strategies

-- Create missing indexes if needed
CREATE INDEX IF NOT EXISTS strategies_user_id_idx ON strategies (user_id);
CREATE INDEX IF NOT EXISTS strategies_status_idx ON strategies (status);
```

### Issue: Version conflict errors too frequent

**Cause**: Multiple users editing same strategy simultaneously or long edit sessions

**Fix**:
- Verify autosave is working (check browser console)
- Consider reducing autosave interval
- Educate users about version conflicts

## Post-Deployment Tasks

### Day 1
- [ ] Monitor error logs for first 4 hours
- [ ] Check authentication success rate
- [ ] Verify strategy creation success rate
- [ ] Review performance metrics

### Week 1
- [ ] Analyze user adoption metrics
- [ ] Review validation error types (identify common mistakes)
- [ ] Check for any security issues
- [ ] Gather user feedback

### Month 1
- [ ] Performance optimization based on real usage
- [ ] Review and tune database indexes
- [ ] Plan for feature enhancements
- [ ] Capacity planning based on growth

## Success Criteria

Feature 004 is considered successfully deployed when:

- [X] All acceptance scenarios from spec.md pass in production
- [X] Success criteria SC-001 through SC-009 are met
- [X] Zero critical bugs in first 48 hours
- [X] User registration and login success rate >99%
- [X] Strategy creation success rate >95%
- [X] Average response time <500ms
- [X] No data loss incidents

## Contacts

- **On-Call Engineer**: [Name/Phone/Email]
- **Database Admin**: [Name/Phone/Email]
- **DevOps Team**: [Slack Channel]
- **Product Owner**: [Name/Email]

## Appendix: Migration SQL

Review these migrations before deployment:

```sql
-- Migration 1: Create users_auth_tables (generated by phx.gen.auth)
CREATE TABLE users (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  email CITEXT NOT NULL UNIQUE,
  hashed_password VARCHAR(255) NOT NULL,
  confirmed_at TIMESTAMP,
  inserted_at TIMESTAMP NOT NULL,
  updated_at TIMESTAMP NOT NULL
);

CREATE TABLE users_tokens (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  token BYTEA NOT NULL,
  context VARCHAR(255) NOT NULL,
  sent_to VARCHAR(255),
  inserted_at TIMESTAMP NOT NULL
);

CREATE INDEX users_email_index ON users (email);
CREATE INDEX users_tokens_user_id_index ON users_tokens (user_id);
CREATE UNIQUE INDEX users_tokens_context_token_index ON users_tokens (context, token);

-- Migration 2: Add user fields to strategies
ALTER TABLE strategies ADD COLUMN user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE;
ALTER TABLE strategies ADD COLUMN lock_version INTEGER NOT NULL DEFAULT 1;
ALTER TABLE strategies ADD COLUMN metadata JSONB;

CREATE INDEX strategies_user_id_idx ON strategies (user_id);
DROP INDEX IF EXISTS strategies_name_version_idx;
CREATE UNIQUE INDEX strategies_user_name_version_idx ON strategies (user_id, name, version);
```

---

**Runbook Version**: 1.0
**Last Updated**: 2026-02-09
**Next Review**: After deployment
