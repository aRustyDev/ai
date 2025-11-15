# Method Plan: Username Resource

## Overview
Usernames in Addy.io function similarly to custom domains but scoped as user-managed alias namespaces. A username can have activation, catch-all, login permission toggles, a default recipient, description/from_name metadata, and optional on‑the‑fly alias creation pattern (`auto_create_regex`). They are mutable except for the core `username` value itself, which appears immutable after creation (no PATCH support for changing username). Therefore:

- Terraform Resource: `addy_username`
- Data Sources:
  - `addy_usernames` (list) for inventory (id, username, active, catch_all, can_login, alias counts).
  - `addy_username` (single) optional for lookup/reference of unmanaged usernames.
- Toggle endpoints consolidated into boolean attributes: `active`, `catch_all`, `can_login`.
- Default recipient managed through dedicated endpoint.

## OpenAPI Endpoints Used
| Purpose | HTTP | Endpoint |
|---------|------|----------|
| List usernames | GET | /api/v1/usernames |
| Create username | POST | /api/v1/usernames |
| Read single username | GET | /api/v1/usernames/{id} |
| Update username (description, from_name, auto_create_regex) | PATCH | /api/v1/usernames/{id} |
| Delete username | DELETE | /api/v1/usernames/{id} |
| Update default recipient | PATCH | /api/v1/usernames/{id}/default-recipient |
| Activate username | POST | /api/v1/active-usernames |
| Deactivate username | DELETE | /api/v1/active-usernames/{id} |
| Enable catch-all | POST | /api/v1/catch-all-usernames |
| Disable catch-all | DELETE | /api/v1/catch-all-usernames/{id} |
| Allow login | POST | /api/v1/loginable-usernames |
| Disallow login | DELETE | /api/v1/loginable-usernames/{id} |

## Terraform Method Mapping
| Terraform Method | Backing Endpoints | Notes |
|------------------|-------------------|-------|
| Create | POST /usernames (+ optional activation, catch-all, login, default-recipient endpoints) | Primary POST only includes `username` (and possibly description/from_name/auto_create_regex if supported). Then reconcile toggles and default recipient. |
| Read | GET /usernames/{id} | Canonical state retrieval; includes counts, flags, timestamps. |
| Update | PATCH /usernames/{id}; toggle endpoints; default-recipient PATCH | Apply changes to mutable fields (description, from_name, auto_create_regex, default_recipient). Reconcile `active`, `catch_all`, `can_login`. |
| Delete | DELETE /usernames/{id} | Remove username. |
| Data Source (List) | GET /usernames | Returns all usernames with counts and flags (no pagination in spec examples; future-proof optional). |
| Data Source (Single) | GET /usernames/{id} | Optional; for referencing externally managed username. |

## Attribute Classification
| Attribute | Source | Terraform Classification | Reason |
|-----------|--------|--------------------------|--------|
| id | Response | Computed | Server UUID. |
| username | Create body; response | Required + ForceNew | Not patchable; immutable identifier. |
| description | Create/PATCH (optional) | Optional | Mutable via PATCH. |
| from_name | Create/PATCH (optional) | Optional | Mutable via PATCH. |
| auto_create_regex | Create/PATCH (optional) | Optional | Mutable pattern controlling on-the-fly alias creation. |
| active | Activation endpoints + response | Optional + Computed | Managed via POST/DELETE active-usernames. |
| catch_all | Toggle endpoints + response | Optional + Computed | Managed via POST/DELETE catch-all-usernames. |
| can_login | Toggle endpoints + response | Optional + Computed | Managed via POST/DELETE loginable-usernames. |
| default_recipient | PATCH /{id}/default-recipient; response object or null | Optional + Computed | Can be set/changed after creation; server authoritative. |
| aliases_count | Response | Computed | Metrics count of aliases under this username. |
| created_at | Response | Computed | Timestamp. |
| updated_at | Response | Computed | Timestamp. |
| user_id | Response | Computed | Correlation/debug only. |

(If response returns a nested default_recipient object, initially expose only its ID: `default_recipient_id`. Expand later if needed.)

## ForceNew Criteria
- `username` immutable: any planned change triggers replacement.
- All other attributes patchable or toggleable → no ForceNew.

## Create Flow (Detailed)
1. Validate `username` non-empty & meets any documented constraints (length/charset if known; if absent, defer validation).
2. Build POST body:
   - Required: `username`
   - Optional: include `description`, `from_name`, `auto_create_regex` if user supplied.
3. POST /api/v1/usernames → capture `id`.
4. Reconcile toggles:
   - If desired `active != response.active` → POST or DELETE active endpoints.
   - If desired `catch_all != response.catch_all` → POST or DELETE catch-all endpoints.
   - If desired `can_login != response.can_login` → POST or DELETE loginable endpoints.
5. Default recipient:
   - If user sets `default_recipient` and differs from response: PATCH /usernames/{id}/default-recipient.
6. Final Read: GET /usernames/{id} for normalized state.

## Update Flow
1. Diff patchable attributes: `description`, `from_name`, `auto_create_regex`.
2. If any changed → PATCH /usernames/{id}.
3. Default recipient changed → PATCH /usernames/{id}/default-recipient.
4. Toggles:
   - active / catch_all / can_login reconciled via their respective endpoints.
5. Final Read: GET /usernames/{id}.

## Delete Flow
- DELETE /api/v1/usernames/{id}`.
- Ignore 404 if resource already removed.

## Read Behavior
- Load all computed attributes.
- Represent absent default recipient as Terraform null.
- Accept natural drift for counts (`aliases_count`) and timestamps.

## Data Source (List) Behavior
- GET /api/v1/usernames.
- Return list of objects with: id, username, active, catch_all, can_login, aliases_count, created_at, updated_at.
- Consider optional flag to include extended attributes (description, from_name, auto_create_regex, default_recipient_id).

## Data Source (Single) Behavior
- GET /api/v1/usernames/{id}.
- Expose full set of attributes (read-only).

## Attribute Modeling Notes
- `default_recipient`: Use `StringAttribute` Optional + Computed. Setting to empty string to clear may require API semantics—if clearing not documented, either skip clearing or provide explicit separate attribute later.
- `auto_create_regex`: Consider adding basic Terraform validation (non-empty when provided).
- `can_login`: Ensure transitions reflect plan; enabling/disabling should integrate with update logic.

## Toggle Endpoint Mapping
| Attribute | Enable Endpoint | Disable Endpoint |
|-----------|-----------------|------------------|
| active | POST /active-usernames | DELETE /active-usernames/{id} |
| catch_all | POST /catch-all-usernames | DELETE /catch-all-usernames/{id} |
| can_login | POST /loginable-usernames | DELETE /loginable-usernames/{id} |

## Error Handling Expectations
| Scenario | Status | Handling |
|----------|--------|----------|
| Create success | 201 | Proceed to toggles; then read. |
| Update success | 200 | Re-read. |
| Delete success | 204 | Remove state. |
| Activation/catch-all/login toggle success | 200 | Continue; re-read. |
| Validation error | 422 | Map via errors.toml → diagnostic. |
| Not found | 404 | During Read after deletion → treat as gone; otherwise diagnostic. |
| Rate limit | 429 | Retry with backoff. |
| Server error | 5xx | Diagnostic; abort. |

## Logging Plan
- Each CRUD operation entry/exit: `tflog.Debug` with `username_id` and `operation`.
- Toggle calls: log endpoint and resulting status.
- Do not log user-supplied `auto_create_regex` if potentially sensitive (usually safe; still truncated if very long).

## Testing Plan Outline
Unit (mock):
- Create username with minimal fields.
- Create with all optional fields + toggles true.
- Update description/from_name/auto_create_regex.
- Toggle active false → true.
- Toggle catch_all and can_login.
- Change default_recipient.
- ForceNew test: change username → plan must replace (simulate in test logic).
- 422 validation error simulation.
- 429 retry logic.

Acceptance (TF_ACC):
- Create username (active=true, catch_all=true, can_login=true).
- Update attributes.
- Toggle off can_login then back on.
- Assign default_recipient after creating recipient resource.
- Destroy.

## Edge Cases & Notes
- If enabling catch_all requires prior activation (verify API tolerance), sequence operations: ensure active first before catch_all (if needed).
- Some endpoints may return 204 vs 200; code should handle both gracefully.
- If default recipient object returned contains nested fields but only ID needed, keep lean state to reduce complexity.
- Drift: `aliases_count` may change outside Terraform; accept as read-only computed.

## Method Plan Table (Summary)

```
Method Plan (username):
# Create: POST /api/v1/usernames -> body: username (+ optional description, from_name, auto_create_regex)
# Read:   GET /api/v1/usernames/{id}
# Update: PATCH /api/v1/usernames/{id} (description, from_name, auto_create_regex), PATCH /usernames/{id}/default-recipient, toggle endpoints for active/catch_all/can_login
# Delete: DELETE /api/v1/usernames/{id}
# Toggles: POST/DELETE active-usernames, catch-all-usernames, loginable-usernames => active, catch_all, can_login
# Immutable (ForceNew): username
# Computed: id, aliases_count, created_at, updated_at, user_id
# Optional+Computed: active, catch_all, can_login, default_recipient_id
# Deferred: clearing default_recipient if API requires undocumented semantics
```

## Next Steps After Username Implementation
- Unify toggle reconciliation logic with domain & alias for DRY principle.
- Add shared validation helpers (e.g., regex pattern sanity checks).
- Implement recipient existence check before setting as default recipient.
- Consider a future composite resource for ordering or grouping usernames if feature emerges.

---
# End of Username Method Plan
