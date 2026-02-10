# Manual Testing Checklist: Strategy UI (Feature 004)

**Feature**: Strategy Registration and Validation UI
**Date**: 2026-02-09
**Tester**: _______________
**Environment**: [ ] Local Dev [ ] Staging [ ] Production
**Browser**: [ ] Chrome [ ] Firefox [ ] Safari [ ] Edge
**Version**: _______________

## Pre-Test Setup

- [ ] Server is running (`mix phx.server`)
- [ ] Database is migrated (`mix ecto.migrate`)
- [ ] No existing user account (or use test credentials)
- [ ] Browser console is open (F12) to check for errors

---

## 1. Authentication Tests

### 1.1 User Registration
- [ ] Navigate to `http://localhost:4000/users/register`
- [ ] Fill in email: `test@example.com`
- [ ] Fill in password: `SecurePassword123!`
- [ ] Click "Register"
- [ ] **Expected**: Redirect to dashboard/login success
- [ ] **Expected**: No JavaScript errors in console

**Result**: [ ] PASS [ ] FAIL
**Notes**: ________________________________________________

### 1.2 User Login
- [ ] Navigate to `http://localhost:4000/users/log_in`
- [ ] Enter credentials from 1.1
- [ ] Click "Log in"
- [ ] **Expected**: Redirect to `/strategies`
- [ ] **Expected**: Welcome message or user email displayed

**Result**: [ ] PASS [ ] FAIL
**Notes**: ________________________________________________

### 1.3 User Logout
- [ ] Click logout button/link
- [ ] **Expected**: Redirect to login page
- [ ] **Expected**: Cannot access `/strategies` without re-login

**Result**: [ ] PASS [ ] FAIL
**Notes**: ________________________________________________

---

## 2. Strategy List Tests

### 2.1 Empty State
- [ ] Login and navigate to `/strategies`
- [ ] **Expected**: "No strategies found" message
- [ ] **Expected**: "Create your first strategy" link/button
- [ ] **Expected**: Page loads in <2 seconds

**Result**: [ ] PASS [ ] FAIL
**Performance**: Load time: _______ seconds
**Notes**: ________________________________________________

### 2.2 Create First Strategy (via link)
- [ ] Click "Create your first strategy" link
- [ ] **Expected**: Navigate to `/strategies/new`
- [ ] **Expected**: Form displays with all fields

**Result**: [ ] PASS [ ] FAIL
**Notes**: ________________________________________________

### 2.3 Filter by Status
- [ ] Create strategies with different statuses (draft, active, inactive)
- [ ] Click "Drafts" tab
- [ ] **Expected**: Only draft strategies shown
- [ ] Click "Active" tab
- [ ] **Expected**: Only active strategies shown
- [ ] Click "All" tab
- [ ] **Expected**: All strategies shown

**Result**: [ ] PASS [ ] FAIL
**Notes**: ________________________________________________

### 2.4 User Isolation
- [ ] Login as User A
- [ ] Create a strategy named "User A Strategy"
- [ ] Logout
- [ ] Register/login as User B
- [ ] Navigate to `/strategies`
- [ ] **Expected**: "User A Strategy" does NOT appear
- [ ] **Expected**: Only User B's strategies visible

**Result**: [ ] PASS [ ] FAIL
**Notes**: ________________________________________________

---

## 3. Strategy Creation Tests (User Story 1)

### 3.1 Form Display
- [ ] Navigate to `/strategies/new`
- [ ] **Expected**: All required fields present:
  - [ ] Name field
  - [ ] Description field
  - [ ] Trading Pair field
  - [ ] Timeframe dropdown
  - [ ] Format dropdown (YAML/TOML)
  - [ ] Content textarea
- [ ] **Expected**: "Create Strategy" button visible

**Result**: [ ] PASS [ ] FAIL
**Notes**: ________________________________________________

### 3.2 Required Field Validation (User Story 2)
- [ ] Leave "Name" field empty
- [ ] Click "Create Strategy"
- [ ] **Expected**: Error message "can't be blank" appears below Name field
- [ ] **Expected**: Validation appears within 1 second

**Validation Response Time**: _______ ms
**Result**: [ ] PASS [ ] FAIL
**Notes**: ________________________________________________

### 3.3 Real-Time Validation
- [ ] Type "AB" in Name field (too short)
- [ ] **Expected**: Error "must be at least 3 characters"
- [ ] Type "ABC"
- [ ] **Expected**: Error disappears
- [ ] **Expected**: Validation feedback within 1 second

**Validation Response Time**: _______ ms
**Result**: [ ] PASS [ ] FAIL
**Notes**: ________________________________________________

### 3.4 Uniqueness Validation
- [ ] Create a strategy named "Test Strategy"
- [ ] Navigate to `/strategies/new` again
- [ ] Enter name "Test Strategy"
- [ ] Tab out of Name field (triggers blur validation)
- [ ] **Expected**: "A strategy with this name already exists" error
- [ ] Change name to "Test Strategy 2"
- [ ] **Expected**: Error disappears

**Result**: [ ] PASS [ ] FAIL
**Notes**: ________________________________________________

### 3.5 Successful Strategy Creation
- [ ] Fill all required fields:
  - Name: "RSI Mean Reversion"
  - Description: "Buy on RSI < 30, sell on RSI > 70"
  - Trading Pair: "BTC/USD"
  - Timeframe: "1h"
  - Format: "yaml"
  - Content:
    ```yaml
    indicators:
      - type: rsi
        name: rsi_14
        parameters:
          period: 14
    entry_conditions: "rsi_14 < 30"
    exit_conditions: "rsi_14 > 70"
    ```
- [ ] Click "Create Strategy"
- [ ] **Expected**: Success message
- [ ] **Expected**: Redirect to strategy detail or list
- [ ] **Expected**: Strategy appears in list

**Result**: [ ] PASS [ ] FAIL
**Notes**: ________________________________________________

---

## 4. Strategy Editing Tests (User Story 3)

### 4.1 View Strategy Details
- [ ] From strategy list, click on "RSI Mean Reversion"
- [ ] **Expected**: Navigate to `/strategies/:id`
- [ ] **Expected**: All strategy details displayed:
  - [ ] Name
  - [ ] Description
  - [ ] Status badge
  - [ ] Version number
  - [ ] Trading pair
  - [ ] Timeframe
  - [ ] DSL content
- [ ] **Expected**: "Edit" button visible

**Result**: [ ] PASS [ ] FAIL
**Notes**: ________________________________________________

### 4.2 Edit Draft Strategy
- [ ] Ensure strategy status is "draft"
- [ ] Click "Edit" button
- [ ] **Expected**: Navigate to `/strategies/:id/edit`
- [ ] **Expected**: Form pre-populated with strategy data
- [ ] Change description to "Updated description"
- [ ] Click "Save"
- [ ] **Expected**: Success message
- [ ] **Expected**: Description updated on detail page

**Result**: [ ] PASS [ ] FAIL
**Notes**: ________________________________________________

### 4.3 Prevent Editing Active Strategy
- [ ] Activate a strategy (set status to "active")
- [ ] Navigate to strategy detail page
- [ ] **Expected**: "Edit" button disabled OR shows error tooltip
- [ ] Try to navigate to `/strategies/:id/edit` directly
- [ ] **Expected**: Error message "Cannot edit active strategy"

**Result**: [ ] PASS [ ] FAIL
**Notes**: ________________________________________________

### 4.4 Version Conflict Detection
**Setup**: Open same strategy in two browser tabs
- [ ] Tab 1: Navigate to `/strategies/:id/edit`
- [ ] Tab 2: Navigate to `/strategies/:id/edit`
- [ ] Tab 1: Change name to "Strategy A"
- [ ] Tab 1: Click "Save"
- [ ] **Expected**: Save succeeds
- [ ] Tab 2: Change name to "Strategy B"
- [ ] Tab 2: Click "Save"
- [ ] **Expected**: Error message "Strategy modified elsewhere. Form reloaded."
- [ ] **Expected**: Form reloads with latest data (name = "Strategy A")

**Result**: [ ] PASS [ ] FAIL
**Notes**: ________________________________________________

---

## 5. Syntax Testing Tests (User Story 4)

### 5.1 Test Valid Syntax
- [ ] Navigate to `/strategies/new`
- [ ] Enter valid YAML content (from section 3.5)
- [ ] Click "Test Syntax" button
- [ ] **Expected**: Success message with parsed summary
- [ ] **Expected**: Response within 3 seconds
- [ ] **Expected**: Summary shows:
  - [ ] Indicator count
  - [ ] Entry conditions
  - [ ] Exit conditions

**Syntax Test Duration**: _______ seconds
**Result**: [ ] PASS [ ] FAIL
**Notes**: ________________________________________________

### 5.2 Test Invalid Syntax
- [ ] Enter invalid YAML content:
  ```yaml
  indicators:
    - type: invalid_indicator_type
      name: bad
      parameters:
        period: "not a number"
  ```
- [ ] Click "Test Syntax"
- [ ] **Expected**: Error message displayed
- [ ] **Expected**: Specific error details (e.g., "Unknown indicator type")
- [ ] **Expected**: Response within 3 seconds

**Syntax Test Duration**: _______ seconds
**Result**: [ ] PASS [ ] FAIL
**Notes**: ________________________________________________

---

## 6. Duplication Tests (User Story 5)

### 6.1 Duplicate Strategy from Detail Page
- [ ] Navigate to strategy detail page
- [ ] Click "Duplicate" button
- [ ] **Expected**: New strategy created
- [ ] **Expected**: Name = "[Original Name] - Copy"
- [ ] **Expected**: Status = "draft"
- [ ] **Expected**: Redirect to new strategy's detail page

**Result**: [ ] PASS [ ] FAIL
**Notes**: ________________________________________________

### 6.2 Duplicate Independence
- [ ] Modify the duplicated strategy (change name to "Modified Copy")
- [ ] Navigate to original strategy
- [ ] **Expected**: Original strategy unchanged
- [ ] **Expected**: Name still "RSI Mean Reversion"

**Result**: [ ] PASS [ ] FAIL
**Notes**: ________________________________________________

### 6.3 Duplicate from List Page
- [ ] Navigate to `/strategies`
- [ ] Find strategy card
- [ ] Click duplicate icon/button on card
- [ ] **Expected**: New strategy created with " - Copy" suffix
- [ ] **Expected**: Page updates to show both strategies

**Result**: [ ] PASS [ ] FAIL
**Notes**: ________________________________________________

---

## 7. Advanced Features Tests (Phase 8)

### 7.1 Indicator Builder Component
- [ ] Navigate to `/strategies/new`
- [ ] Click "Add Indicator" button
- [ ] **Expected**: Indicator form appears
- [ ] Select "RSI" from dropdown
- [ ] **Expected**: Period field appears
- [ ] Enter period: 14
- [ ] Click "Add"
- [ ] **Expected**: Indicator added to list
- [ ] **Expected**: DSL content updates automatically

**Result**: [ ] PASS [ ] FAIL
**Notes**: ________________________________________________

### 7.2 Condition Builder Component
- [ ] Click "Add Entry Condition"
- [ ] **Expected**: Condition builder appears
- [ ] Build condition: "rsi_14 < 30"
- [ ] Click "Add"
- [ ] **Expected**: Condition added
- [ ] **Expected**: DSL content updates

**Result**: [ ] PASS [ ] FAIL
**Notes**: ________________________________________________

---

## 8. Autosave Tests

### 8.1 Autosave Draft
- [ ] Navigate to `/strategies/new`
- [ ] Fill in Name: "Autosave Test"
- [ ] Fill in other required fields
- [ ] Wait 30+ seconds (do not click save)
- [ ] **Expected**: "Draft saved" notification OR indicator
- [ ] Refresh the page
- [ ] **Expected**: Form data persists (name = "Autosave Test")

**Result**: [ ] PASS [ ] FAIL
**Notes**: ________________________________________________

---

## 9. Performance Tests

### 9.1 List Load Performance (Success Criteria SC-004)
**Setup**: Create 100+ strategies
- [ ] Navigate to `/strategies`
- [ ] Measure page load time
- [ ] **Expected**: Loads in <2 seconds
- [ ] **Expected**: All strategies render correctly

**Load Time**: _______ seconds
**Result**: [ ] PASS [ ] FAIL
**Notes**: ________________________________________________

### 9.2 Validation Response Time (Success Criteria SC-002)
- [ ] Navigate to `/strategies/new`
- [ ] Enter invalid data in Name field
- [ ] Measure time until error appears
- [ ] **Expected**: <1 second

**Validation Time**: _______ ms
**Result**: [ ] PASS [ ] FAIL
**Notes**: ________________________________________________

### 9.3 Syntax Test Performance (Success Criteria SC-005)
- [ ] Enter strategy with 10 indicators
- [ ] Click "Test Syntax"
- [ ] Measure response time
- [ ] **Expected**: <3 seconds

**Syntax Test Time**: _______ seconds
**Result**: [ ] PASS [ ] FAIL
**Notes**: ________________________________________________

---

## 10. Cross-Browser Tests

### 10.1 Chrome
- [ ] All tests above pass in Chrome

**Result**: [ ] PASS [ ] FAIL

### 10.2 Firefox
- [ ] Registration/Login works
- [ ] Strategy creation works
- [ ] Real-time validation works
- [ ] No console errors

**Result**: [ ] PASS [ ] FAIL

### 10.3 Safari (macOS)
- [ ] Basic functionality works
- [ ] LiveView updates work correctly

**Result**: [ ] PASS [ ] FAIL

---

## 11. Edge Cases & Error Handling

### 11.1 Large DSL Content
- [ ] Create strategy with 5000+ lines of YAML
- [ ] Save successfully
- [ ] Edit and save again
- [ ] **Expected**: No timeout or errors

**Result**: [ ] PASS [ ] FAIL
**Notes**: ________________________________________________

### 11.2 Special Characters in Name
- [ ] Create strategy with name: "Strategy with 'quotes' and \"escapes\""
- [ ] **Expected**: Saves without SQL errors
- [ ] **Expected**: Displays correctly

**Result**: [ ] PASS [ ] FAIL
**Notes**: ________________________________________________

### 11.3 Network Interruption
- [ ] Start creating a strategy
- [ ] Disable network connection
- [ ] Click "Save"
- [ ] **Expected**: Error message or retry mechanism
- [ ] Re-enable network
- [ ] **Expected**: Can retry save

**Result**: [ ] PASS [ ] FAIL
**Notes**: ________________________________________________

---

## Summary

**Total Tests**: 50+
**Passed**: _______
**Failed**: _______
**Blocked**: _______
**Pass Rate**: _______%

**Critical Failures**:
________________________________________________
________________________________________________

**Recommendations**:
________________________________________________
________________________________________________

**Sign-off**:
- [ ] All critical tests pass
- [ ] Performance criteria met
- [ ] No major bugs found
- [ ] Ready for deployment

**Tester Signature**: _______________ **Date**: ___________
**Reviewer Signature**: _______________ **Date**: ___________
