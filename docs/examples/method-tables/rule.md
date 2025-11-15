# Method Plan: Rule Resource

## Overview
Rules define conditional logic applied to inbound/outbound email flows (forward, reply, send) for aliases. They consist of ordered conditions and actions, plus enablement flags (forwards, replies, sends) and an operator (AND/OR). Rules are mutable: created, updated, activated/deactivated, reordered, and deleted. Therefore:

- Terraform Resource: `addy_rule`
- Data Sources:
  - `addy_rules` (list) – for inventory and ordering visibility.
  - `addy_rule` (single) – optional if referencing non-managed rule.
- Activation modeled via a boolean `active` attribute.
- Ordering managed through separate endpoint (`/api/v1/reorder-rules`); initially not automatically managed per resource to avoid unintended global side effects.

## OpenAPI Endpoints Used
| Purpose | HTTP | Endpoint |
|---------|------|----------|
| List rules | GET | /api/v1/rules |
| Create rule | POST | /api/v1/rules |
| Read single rule | GET | /api/v1/rules/{id} |
| Update rule | PATCH | /api/v1/rules/{id} |
| Delete rule | DELETE | /api/v1/rules/{id} |
| Activate rule | POST | /api/v1/active-rules |
| Deactivate rule | DELETE | /api/v1/active-rules/{id} |
| Reorder rules (global ordering) | POST | /api/v1/reorder-rules |

## Terraform Method Mapping
| Terraform Method | Backing Endpoints | Notes |
|------------------|-------------------|-------|
| Create | POST /rules (+ optional POST /active-rules; reorder endpoint deferred) | Create JSON includes name, conditions, actions, operator, forwards/replies/sends, active. |
| Read | GET /rules/{id} | Canonical state retrieval; includes applied counts, last_applied timestamps. |
| Update | PATCH /rules/{id}; activation endpoints; optional reorder (deferred) | Update mutable fields; reconcile `active` toggle. |
| Delete | DELETE /rules/{id} | Remove rule from system. |
| Data Source (List) | GET /rules | Returns array; can surface order and active status. |
| Data Source (Single) | GET /rules/{id} | Optional lookup outside resource management. |
| Reorder (Global) | POST /reorder-rules | Future optional operation; may require composite resource or separate meta resource. Deferred for MVP. |

## Attribute Classification
| Attribute | Source | Terraform Classification | Reason |
|-----------|--------|--------------------------|--------|
| id | Response create/read | Computed | UUID from server. |
| name | Create/PATCH | Required (or Optional?) → Recommended Required | Critical identifier; patchable. |
| conditions | Create/PATCH | Required (Nested List) | Must define at least one condition logically; API shows array structure. |
| actions | Create/PATCH | Required (Nested List) | At least one action typically required; API uses array. |
| operator | Create/PATCH | Required | Explicit AND/OR selection; patchable. |
| forwards | Create/PATCH | Optional | Boolean controlling apply to forwarded emails; patchable. |
| replies | Create/PATCH | Optional | Boolean controlling apply to replies; patchable. |
| sends | Create/PATCH | Optional | Boolean controlling apply to sends; patchable. |
| active | Activation endpoints + response | Optional + Computed | Managed via POST/DELETE /active-rules. |
| order | Response list (?) | Computed | Server-controlled ordering index. (Not exposed in create body; not patchable individually.) |
| applied | Response | Computed | Count of times rule applied. |
| last_applied | Response (nullable) | Computed | Null until first application. |
| created_at | Response | Computed | Timestamp. |
| updated_at | Response | Computed | Timestamp. |
| user_id | Response | Computed | Correlation only. |

### Nested Blocks

#### Condition Block
| Field | Classification | Notes |
|-------|----------------|------|
| type | Required | Must be one of: sender, subject, alias, alias_description (per spec). |
| match | Required | One of: is exactly, is not, contains, does not contain, starts with, does not start with, ends with, does not end with, matches regex, does not match regex. |
| values | Required (List of String) | Non-empty; server expects array. |

#### Action Block
| Field | Classification | Notes |
|-------|----------------|------|
| type | Required | One of: subject, displayFrom, encryption, banner, block, removeAttachments, forwardTo. |
| value | Required (String) | Semantics vary; for forwardTo, recipient ID; for subject, new subject line; for block maybe ignored by server (some actions may not require value). If action type does not require value, consider optional → refine after empirical test. |

## ForceNew Criteria
None initially:
- Name, conditions, actions, operator, forwards/replies/sends all patchable.
- If future immutability arises (e.g., rule type classification), adjust.

## Create Flow (Detailed)
1. Validate:
   - At least one condition and one action (unless API allows empty arrays—examples show arrays present).
   - Operator in {AND, OR}.
   - Condition match values non-empty.
2. Build JSON:
   - name
   - conditions (array of objects)
   - actions (array of objects)
   - operator
   - forwards/replies/sends
3. POST /api/v1/rules.
4. If desired `active` true and returned rule is not active → POST /active-rules (body: id).
5. Final GET /rules/{id} to normalize state.

## Update Flow
1. Diff each mutable field:
   - If conditions or actions changed: send full new arrays (replace semantics; partial patch not documented).
   - Patch body includes only changed fields OR full set? API examples show full set; safer to send all declared mutate-able fields.
2. PATCH /api/v1/rules/{id}.
3. If `active` changed:
   - True → POST /active-rules
   - False → DELETE /active-rules/{id}
4. Final Read to synchronize.

## Delete Flow
- DELETE /api/v1/rules/{id}.
- Ignore 404 for repeated attempts.

## Read Behavior
- GET /rules/{id}.
- Populate all attributes:
  - Convert last_applied null → Terraform null.
  - Nested arrays preserved in order returned (order matters logically especially if conditions are evaluated sequentially—spec shows an `order` field on rule itself, not necessarily per condition).
- `order` is server-controlled; do NOT attempt to set it unless reorder support added.

## Reorder Handling (Deferred)
- Global reorder endpoint changes relative order of all rules.
- Terraform cannot easily manage global ordering inside individual resources without risk of perpetual drift.
- Future approach:
  - Introduce a separate resource `addy_rules_order` with attribute `ids = [id1, id2, ...]`.
  - That resource uses POST /reorder-rules.
- For MVP: Document that `order` is read-only and external reorders produce drift in `order` attribute only (informational).

## Data Source (List) Behavior
- GET /rules.
- Return list of nested rule objects (subset or full).
- Attributes:
  - id
  - name
  - active
  - order
  - applied
  - last_applied
  - perhaps omit conditions/actions initially for performance (optional flag to include full detail later).

## Data Source (Single)
- GET /rules/{id}
- Returns full definition; useful for referencing external rule logic without management.

## Attribute Modeling Notes
- `conditions` and `actions` as `ListNestedAttribute` with robust validation.
- Consider adding plan-time validation for regex in conditions if `match` is “matches regex”.
- Some action types (block, removeAttachments) may not require `value`; treat `value` as optional for those if confirmed (initially keep required; refine after API behavior test).

## Error Handling Expectations
| Scenario | Status | Handling |
|----------|--------|----------|
| Create success | 201 | Proceed to activation logic if needed. |
| Update success | 200 | Re-read & finalize. |
| Delete success | 204 | Remove state. |
| Activation toggle success | 200 | Re-read. |
| Validation error (bad match/operator/type) | 422 | Diagnostic with mapped meaning. |
| Not found | 404 | If during Read after create → error; after deletion → treat as gone. |
| Rate limit | 429 | Retry with backoff. |
| Server error | 5xx | Diagnostic; abort operation. |

## Logging Plan
- Entry/exit for Create/Update/Delete/Read: `tflog.Debug` with `rule_id` (when available) and `operation`.
- Log counts: number of conditions/actions processed.
- Activation toggling: log endpoint invocation and status.

## Testing Plan Outline
Unit (mock):
- Create rule with single condition + single action.
- Update rule: change operator and add second condition.
- Toggle active on/off.
- Invalid condition (empty values) → expect validation diagnostic.
- Invalid match/operator string → expect 422 mapping.
- Reorder deferred: ensure `order` attribute present in Read.
- Rate limit simulation.

Acceptance (TF_ACC):
- Create rule (active = true).
- Modify conditions (add new).
- Deactivate rule.
- Delete rule.

## Edge Cases & Notes
- Empty conditions or actions arrays: confirm if API rejects; treat empties as invalid unless spec later clarifies.
- Changing ordering externally will alter `order` attribute only—document as non-destructive drift.
- `applied` counter and `last_applied` may change outside Terraform runs; accept as normal drift (Computed).
  - Option: Mark these as “non-sensitive drift” and just refresh state.
- If forwardTo action requires a recipient ID that is not yet verified, expect API 422—surface diagnostic clearly.

## Method Plan Table (Summary)

```
Method Plan (rule):
# Create: POST /api/v1/rules -> body: name, conditions[], actions[], operator, forwards, replies, sends
# Read:   GET /api/v1/rules/{id}
# Update: PATCH /api/v1/rules/{id} (replace arrays + core fields), activation toggle via POST/DELETE active-rules
# Delete: DELETE /api/v1/rules/{id}
# Activate/Deactivate: POST /active-rules | DELETE /active-rules/{id} => active (Optional+Computed)
# Immutable: (None) – all core fields patchable; arrays replaced wholesale
# Computed: id, order, applied, last_applied, created_at, updated_at, user_id
# Deferred: reorder endpoint modeling
```

## Next Steps After Rule Implementation
- Implement `addy_rules` data source with optional inclusion of full condition/action detail.
- Plan specialized resource later for global ordering if user demand arises.
- Reuse nested block validation patterns for other complex entities (if any emerge).

---
# End of Rule Method Plan
