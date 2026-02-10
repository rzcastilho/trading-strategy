# Security Audit Checklist: Strategy UI (Feature 004)

**Feature**: Strategy Registration and Validation UI
**Date**: 2026-02-09
**Auditor**: _______________
**Scope**: Authentication, Authorization, Input Validation, Data Protection

---

## 1. Authentication Security

### 1.1 Password Requirements
- [ ] Minimum password length enforced (12+ characters)
- [ ] Password complexity requirements in place
- [ ] Passwords are hashed using bcrypt (verify in User schema)
- [ ] No plaintext passwords in logs or database
- [ ] Password reset tokens expire after reasonable time

**Verification**:
```bash
# Check User schema
grep -A10 "validate_password" lib/trading_strategy/accounts/user.ex

# Check for plaintext passwords in logs
grep -ri "password" log/ | grep -v "hashed_password"
```

**Result**: [ ] PASS [ ] FAIL
**Notes**: ________________________________________________

### 1.2 Session Management
- [ ] Session secret is generated and secure (SECRET_KEY_BASE)
- [ ] Sessions expire after inactivity
- [ ] Logout properly invalidates sessions
- [ ] No session fixation vulnerabilities
- [ ] CSRF protection enabled for forms

**Verification**:
```bash
# Check for SECRET_KEY_BASE in config
grep "secret_key_base" config/runtime.exs

# Check CSRF protection in router
grep "protect_from_forgery" lib/trading_strategy_web/router.ex
```

**Result**: [ ] PASS [ ] FAIL
**Notes**: ________________________________________________

### 1.3 Brute Force Protection
- [ ] Login attempts are rate limited
- [ ] Account lockout after N failed attempts
- [ ] No username enumeration (same error for invalid user/password)
- [ ] Email confirmation prevents spam registrations

**Manual Test**:
- Try 10+ failed login attempts
- **Expected**: Rate limiting or account lockout

**Result**: [ ] PASS [ ] FAIL
**Notes**: ________________________________________________

---

## 2. Authorization Security

### 2.1 User Isolation
- [ ] All strategy queries filter by `user_id`
- [ ] Cannot access another user's strategies via direct URL
- [ ] Cannot edit another user's strategies
- [ ] Cannot delete another user's strategies

**Manual Test**:
```
1. Login as User A, create strategy, note ID
2. Logout, login as User B
3. Try to access /strategies/{User A's strategy ID}
Expected: 404 or Unauthorized
```

**Result**: [ ] PASS [ ] FAIL
**Notes**: ________________________________________________

### 2.2 Authorization Checks in Context Functions
- [ ] `get_strategy/2` requires user parameter
- [ ] `update_strategy/3` verifies ownership before update
- [ ] `delete_strategy/2` verifies ownership before delete
- [ ] `list_strategies/2` scoped to user

**Code Review**:
```bash
# Verify user scoping in all context functions
grep -A5 "def get_strategy" lib/trading_strategy/strategies.ex
grep -A5 "def update_strategy" lib/trading_strategy/strategies.ex
grep -A5 "def delete_strategy" lib/trading_strategy/strategies.ex
```

**Result**: [ ] PASS [ ] FAIL
**Notes**: ________________________________________________

### 2.3 LiveView Authorization
- [ ] `/strategies` requires authentication
- [ ] `/strategies/new` requires authentication
- [ ] `/strategies/:id/edit` requires authentication AND ownership
- [ ] LiveView mount functions check `current_user`

**Verification**:
```bash
# Check router authentication requirements
grep -A2 "live.*strategies" lib/trading_strategy_web/router.ex | grep "require_authenticated_user"

# Check LiveView mount authorization
grep -A10 "def mount" lib/trading_strategy_web/live/strategy_live/*.ex | grep "current_user"
```

**Result**: [ ] PASS [ ] FAIL
**Notes**: ________________________________________________

---

## 3. Input Validation & SQL Injection

### 3.1 SQL Injection Prevention
- [ ] All database queries use parameterized queries (Ecto does this)
- [ ] No raw SQL with string interpolation
- [ ] Search/filter inputs are sanitized

**Code Review**:
```bash
# Search for dangerous patterns
grep -r "Repo.query" lib/trading_strategy/ | grep "#{"
# Should find NONE

# Check for string interpolation in queries
grep -r "from.*where.*#{" lib/trading_strategy/
# Should find NONE
```

**Result**: [ ] PASS [ ] FAIL
**Notes**: ________________________________________________

### 3.2 Input Validation in Changesets
- [ ] Name field: length validation (3-200 chars)
- [ ] Trading pair: format validation
- [ ] Timeframe: enum validation (only allowed values)
- [ ] Format: enum validation (only "yaml" or "toml")
- [ ] DSL content: validation before execution

**Code Review**:
```bash
# Check Strategy changeset validations
grep -A30 "def changeset" lib/trading_strategy/strategies/strategy.ex
```

**Result**: [ ] PASS [ ] FAIL
**Notes**: ________________________________________________

### 3.3 File Upload Security (if applicable)
- [ ] No file uploads in current feature (PASS by default)
- [ ] If DSL content upload added: validate file type, size, content

**Result**: [ ] PASS [ ] N/A
**Notes**: ________________________________________________

---

## 4. Cross-Site Scripting (XSS) Prevention

### 4.1 Output Encoding
- [ ] All user input is HTML-escaped by default (Phoenix does this)
- [ ] No use of `raw/1` or `Phoenix.HTML.raw/1` for user data
- [ ] Strategy names displayed safely
- [ ] Strategy descriptions displayed safely
- [ ] DSL content displayed safely (code blocks)

**Code Review**:
```bash
# Search for dangerous raw HTML rendering
grep -r "raw(" lib/trading_strategy_web/
grep -r "Phoenix.HTML.raw" lib/trading_strategy_web/
```

**Manual Test**:
1. Create strategy with name: `<script>alert('XSS')</script>`
2. View strategy list and detail pages
3. **Expected**: Script NOT executed, displayed as text

**Result**: [ ] PASS [ ] FAIL
**Notes**: ________________________________________________

### 4.2 JavaScript Injection in Attributes
- [ ] Form inputs use proper attribute escaping
- [ ] No user data in `onclick`, `onerror` attributes
- [ ] LiveView bindings are safe

**Manual Test**:
1. Create strategy with description containing: `" onload="alert('XSS')"`
2. **Expected**: No alert, safely encoded

**Result**: [ ] PASS [ ] FAIL
**Notes**: ________________________________________________

---

## 5. Cross-Site Request Forgery (CSRF)

### 5.1 CSRF Token Validation
- [ ] All forms include CSRF token
- [ ] Phoenix `protect_from_forgery` plug enabled
- [ ] LiveView forms protected (LiveView handles this)
- [ ] API endpoints (if any) use proper authentication

**Code Review**:
```bash
# Check for CSRF protection in router
grep "protect_from_forgery" lib/trading_strategy_web/router.ex

# Check forms have CSRF tokens
grep "csrf_token" lib/trading_strategy_web/components/*.ex
```

**Result**: [ ] PASS [ ] FAIL
**Notes**: ________________________________________________

---

## 6. Sensitive Data Exposure

### 6.1 Logging Security
- [ ] No passwords in logs
- [ ] No user emails in logs (unless masked)
- [ ] No DSL content with API keys in logs
- [ ] Correlation IDs used instead of user IDs where possible

**Code Review**:
```bash
# Search for potential sensitive data logging
grep -r "Logger\." lib/trading_strategy/ | grep -E "(password|api_key|secret)"
```

**Result**: [ ] PASS [ ] FAIL
**Notes**: ________________________________________________

### 6.2 Database Security
- [ ] Passwords are bcrypt hashed
- [ ] No sensitive data in plaintext
- [ ] Database backups are encrypted
- [ ] `metadata` JSONB field doesn't store secrets

**Database Check**:
```sql
-- Check users table structure
\d users

-- Verify hashed_password column exists
SELECT column_name, data_type FROM information_schema.columns
WHERE table_name = 'users' AND column_name = 'hashed_password';
```

**Result**: [ ] PASS [ ] FAIL
**Notes**: ________________________________________________

### 6.3 Error Messages
- [ ] Error messages don't leak sensitive info
- [ ] Stack traces not shown in production
- [ ] Database errors sanitized for users
- [ ] Generic errors for authentication failures

**Manual Test**:
1. Trigger an error (e.g., invalid strategy ID)
2. **Expected**: Generic error, no stack trace
3. Check logs for detailed error (should be there)

**Result**: [ ] PASS [ ] FAIL
**Notes**: ________________________________________________

---

## 7. Access Control

### 7.1 Direct Object Reference (IDOR)
- [ ] Cannot guess strategy IDs (UUIDs used)
- [ ] Cannot access strategies by incrementing IDs
- [ ] Authorization checked before data access

**Manual Test**:
1. User A creates strategy, note UUID
2. User B tries to access `/strategies/{User A's UUID}`
3. **Expected**: 404 or Unauthorized

**Result**: [ ] PASS [ ] FAIL
**Notes**: ________________________________________________

### 7.2 Mass Assignment Protection
- [ ] Cannot set `user_id` via form params
- [ ] Cannot set `lock_version` to bypass conflicts
- [ ] Cannot set `status` to activate without validation
- [ ] Changeset only casts allowed fields

**Code Review**:
```elixir
# Verify Strategy changeset only casts expected fields
# Should NOT include user_id in cast from params
# User ID should be set explicitly in context
```

**Result**: [ ] PASS [ ] FAIL
**Notes**: ________________________________________________

---

## 8. Business Logic Security

### 8.1 Strategy Status Transitions
- [ ] Cannot activate strategy without backtest
- [ ] Cannot edit active strategies
- [ ] Cannot delete active strategies
- [ ] Status transitions validated in context layer

**Manual Test**:
1. Create draft strategy
2. Try to set status="active" via form manipulation
3. **Expected**: Validation error (backtest required)

**Result**: [ ] PASS [ ] FAIL
**Notes**: ________________________________________________

### 8.2 Version Conflict Security
- [ ] Optimistic locking prevents lost updates
- [ ] `lock_version` cannot be manipulated
- [ ] Stale entry errors handled gracefully

**Manual Test**:
1. Open strategy in two sessions
2. Save from session 1
3. Try to save from session 2 with old lock_version
4. **Expected**: Stale entry error

**Result**: [ ] PASS [ ] FAIL
**Notes**: ________________________________________________

---

## 9. Dependency Security

### 9.1 Dependency Audit
- [ ] Run `mix hex.audit` to check for vulnerabilities
- [ ] All dependencies up to date (critical patches)
- [ ] No known CVEs in Phoenix, Ecto, bcrypt

**Verification**:
```bash
mix hex.audit
mix hex.outdated
```

**Result**: [ ] PASS [ ] FAIL
**Notes**: ________________________________________________

---

## 10. Infrastructure Security

### 10.1 HTTPS Enforcement
- [ ] Production runs on HTTPS only
- [ ] HTTP redirects to HTTPS
- [ ] Secure cookies (`:secure` flag in production)
- [ ] HSTS header configured

**Production Check**:
```bash
curl -I http://your-domain.com | grep "Location: https"
curl -I https://your-domain.com | grep "Strict-Transport-Security"
```

**Result**: [ ] PASS [ ] FAIL [ ] N/A (local dev)
**Notes**: ________________________________________________

### 10.2 Security Headers
- [ ] `X-Frame-Options: DENY` or `SAMEORIGIN`
- [ ] `X-Content-Type-Options: nosniff`
- [ ] `X-XSS-Protection: 1; mode=block`
- [ ] Content Security Policy (CSP) configured

**Verification**:
```bash
curl -I https://your-domain.com | grep "X-Frame-Options"
curl -I https://your-domain.com | grep "X-Content-Type-Options"
```

**Result**: [ ] PASS [ ] FAIL [ ] N/A (local dev)
**Notes**: ________________________________________________

---

## 11. Rate Limiting & DoS Protection

### 11.1 Rate Limiting
- [ ] Login endpoint rate limited
- [ ] Registration endpoint rate limited
- [ ] Strategy creation rate limited (prevent spam)
- [ ] Syntax test endpoint rate limited

**Manual Test**:
1. Attempt 100 rapid requests to `/users/log_in`
2. **Expected**: Rate limit error after N requests

**Result**: [ ] PASS [ ] FAIL [ ] TODO
**Notes**: ________________________________________________

---

## 12. Data Integrity

### 12.1 Uniqueness Constraints
- [ ] User email unique (database constraint)
- [ ] Strategy name unique per user+version (database constraint)
- [ ] Database constraints match application validations

**Database Check**:
```sql
-- Check unique indexes
SELECT indexname, indexdef FROM pg_indexes
WHERE tablename = 'users' OR tablename = 'strategies';
```

**Result**: [ ] PASS [ ] FAIL
**Notes**: ________________________________________________

---

## Summary

**Total Checks**: 50+
**Passed**: _______
**Failed**: _______
**Not Applicable**: _______

**Critical Vulnerabilities Found**:
________________________________________________
________________________________________________

**Medium/Low Issues**:
________________________________________________
________________________________________________

**Remediation Required**:
- [ ] Critical: _______________________________________
- [ ] High: __________________________________________
- [ ] Medium: ________________________________________

**Security Sign-off**:
- [ ] No critical vulnerabilities
- [ ] All high-priority issues resolved
- [ ] Medium issues documented for future fix
- [ ] Ready for production deployment

**Auditor Signature**: _______________ **Date**: ___________
**Security Lead Approval**: _______________ **Date**: ___________

---

## Appendix: Quick Security Checks

### Run These Commands

```bash
# 1. Dependency audit
mix hex.audit

# 2. Check for dangerous patterns
grep -r "raw(" lib/trading_strategy_web/
grep -r "Repo.query.*#{" lib/
grep -ri "password.*Logger" lib/

# 3. Database constraints
psql -d trading_strategy_dev -c "\d users"
psql -d trading_strategy_dev -c "\d strategies"

# 4. Test CSRF protection
# Try submitting form without CSRF token (should fail)

# 5. Test user isolation
# Create strategy as User A, try to access as User B
```

### OWASP Top 10 2021 Checklist

- [ ] A01:2021-Broken Access Control → Tested (User Isolation)
- [ ] A02:2021-Cryptographic Failures → Tested (Password Hashing)
- [ ] A03:2021-Injection → Tested (SQL Injection, XSS)
- [ ] A04:2021-Insecure Design → Tested (Business Logic)
- [ ] A05:2021-Security Misconfiguration → Tested (Headers, HTTPS)
- [ ] A06:2021-Vulnerable Components → Tested (Dependencies)
- [ ] A07:2021-Authentication Failures → Tested (Auth System)
- [ ] A08:2021-Data Integrity Failures → Tested (Optimistic Locking)
- [ ] A09:2021-Logging Failures → Tested (No Sensitive Data)
- [ ] A10:2021-SSRF → N/A (No external requests from user input)
