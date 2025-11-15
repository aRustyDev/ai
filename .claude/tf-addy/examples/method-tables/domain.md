# Method Plan: Domain Resource

## Overview
The Addy.io Domain entity is mutable. It supports creation, update of selected fields, activation/deactivation, catch-all toggling, and deletion. It also exposes a default recipient assignment sub-endpoint. Therefore:
- Terraform Resource: `addy_domain`
- Complementary Data Source (list): `addy_domains` (optional: single data source `addy_domain` if lookups needed)
- Toggle endpoints (active, catch-all) are modeled as boolean attributes on the resource instead of separate Terraform resources.

## OpenAPI Endpoints Used
| Purpose | HTTP | Endpoint |
|---------|------|----------|
| List domains | GET | /api/v1/domains |
| Create domain | POST | /api/v1/domains |
| Read single domain | GET | /api/v1/domains/{id} |
| Update domain (description, from_name, auto_create_regex) | PATCH | /api/v1/domains/{id} |
| Delete domain | DELETE | /api/v1/domains/{id} |
| Activate domain | POST | /api/v1/active-domains |
| Deactivate domain | DELETE | /api/v1/active-domains/{id} |
| Enable catch-all | POST | /api/v1/catch-all-domains |
| Disable catch-all | DELETE | /api/v1/catch-all-domains/{id} |
| Update default recipient | PATCH | /api/v1/domains/{id}/default-recipient |

## Terraform Method Mapping
| Terraform Method | Backing Endpoints | Notes |
|------------------|-------------------|-------|
| Create | POST /domains (+ optional POST /active-domains, POST /catch-all-domains, PATCH /domains/{id}/default-recipient) | Perform main POST, then reconcile toggles and default recipient if desired state differs. |
| Read | GET /domains/{id} | Single authoritative fetch after Create/Update to normalize state. |
| Update | PATCH /domains/{id}; Activation & catch-all toggle endpoints; PATCH default-recipient | Diff plan vs current; execute minimal set of calls. |
| Delete | DELETE /domains/{id} | Domain removal; toggles need not be undone first. |
| Data Source (List) | GET /domains | Optionally supports pagination later (API does not show page params currently). |
| Data Source (Single) | GET /domains/{id} | Optional if users need to look up domains not managed by Terraform. |

## Attribute Classification
| Attribute | Source | Terraform Classification | Reason |
|-----------|--------|--------------------------|--------|
| id | Response (create/read) | Computed (Resource ID) | Server generates UUID. |
| domain | Request body (create), response | Required + ForceNew | Cannot be changed after creation (PATCH body does not list domain). |
| description | POST optional, PATCH present | Optional | Mutable via PATCH. |
| from_name | POST optional, PATCH present | Optional | Mutable via PATCH. |
| auto_create_regex | POST optional, PATCH present | Optional | Mutable via PATCH. |
| active | Derived from activation endpoints + response | Optional + Computed (bool) | Managed via separate POST/DELETE; server value authoritative after toggling. |
| catch_all | Derived from catch-all endpoints + response | Optional + Computed (bool) | Same toggle pattern as `active`. |
| default_recipient | PATCH /{id}/default-recipient; response object (or null) | Optional + Computed | Can be set/cleared independently; server returns full structure. |
| aliases_count | Response only | Computed | Server statistic. |
| domain_verified_at | Response only | Computed (nullable) | Verification timestamp. |
| domain_mx_validated_at | Response only | Computed (nullable) | MX validation timestamp. |
| domain_sending_verified_at | Response only | Computed (nullable) | Sending verification timestamp. |
| created_at | Response only | Computed | Creation timestamp. |
| updated_at | Response only | Computed | Last update timestamp. |
| user_id | Response only | Computed (optional include) | Helpful for correlation/debug; not required. |

(Nullable timestamps → use Terraform null semantics when `null`.)

## ForceNew Criteria
- Changing `domain` requires new resource (no API to patch domain).
- If future API adds more immutable fields (none currently), mark them ForceNew.

## Create Flow (Detailed)
1. Build request body: `{ "domain": <required>, "description":?, "from_name":?, "auto_create_regex":? }` (only include non-empty optional fields).
2. POST /api/v1/domains.
3. Capture returned `id` and initial attribute values.
4. Reconcile toggles:
   - If desired `active != response.active` → call POST /active-domains or DELETE /active-domains/{id}.
   - If desired `catch_all != response.catch_all` → POST /catch-all-domains or DELETE /catch-all-domains/{id}.
5. Default recipient:
   - If user set `default_recipient` and response default recipient differs → PATCH /domains/{id}/default-recipient.
6. Final GET /domains/{id} to normalize state into Terraform.

## Update Flow
1. Compare plan vs current state for patchable attributes: description, from_name, auto_create_regex.
2. If any changed → PATCH /domains/{id}.
3. If default_recipient changed (including removal) → PATCH /domains/{id}/default-recipient with new ID or possibly clear (check if API supports clearing by sending null—if not documented, treat removal as no-op or omit clearing until verified).
4. Reconcile toggles:
   - active: if changed → activate/deactivate endpoints.
   - catch_all: same.
5. Final Read: GET /domains/{id}.

## Delete Flow
- DELETE /api/v1/domains/{id}.
- Ignore 404 on re-delete attempts.
- No pre-deactivation needed.

## Read Behavior
- Always map missing timestamps as null values.
- If endpoint returns nested `default_recipient` object, expose only ID (and possibly optional sub-attributes later—initially keep simple to avoid complexity).
- Ensure all declared attributes are set in state (Computed or Null).

## Data Source (List) Behavior (Future)
- GET /api/v1/domains.
- Model as:
  - `domains` = list (or set) of nested objects.
  - Each nested object includes: id, domain, active, catch_all, aliases_count, verification timestamps.
- Optional filtering (none documented currently).

## Error Handling Expectations
| Scenario | Status | Handling |
|----------|--------|----------|
| Successful create | 201 | Proceed; parse body. |
| Successful read/update | 200 | Parse; update state. |
| Successful delete | 204 | Remove from state. |
| Validation error | 422 | Diagnostic with mapped meaning from errors.toml. |
| Not found after delete/read | 404 | If in Read after delete detection → treat as resource gone; if during normal Read → diagnostic. |
| Rate limit | 429 | Retry with backoff policy. |
| Server error | 5xx | Diagnostic; avoid infinite retries. |

## Logging Plan
- Create/Update/Delete/Read entry: `tflog.Debug` with `operation`, `domain_id` (when available), endpoint.
- After HTTP response: log status code & outcome category (success/failure).
- Avoid logging entire response body; include only size or truncated snippet if debugging.

## Testing Plan Outline
Unit (mock transport):
- Create success.
- Create + activation toggle path.
- Update description only.
- Update catch_all only.
- Error: 422 validation.
- Retry logic: simulate 429 then 200.

Acceptance (TF_ACC):
- Create domain.
- Toggle active false → true.
- Toggle catch_all true → false → true.
- Update description/from_name.
- Set default_recipient (once recipient resource exists).
- Destroy domain.

## Edge Cases & Notes
- API examples show `active: true` and `catch_all: true` by default; verify actual defaults with real API before assuming.
- Clearing default recipient may require explicit semantics (if unsupported by API, document limitation).
- `auto_create_regex` may need validation: ensure user passes valid pattern (consider optional local validation later).
- Domain verification timestamps may remain null for extended periods—represent consistently as null, not empty string.

## Next Steps After Implementing Domain
- Reuse pattern for alias resource (similar activation & limiting toggles).
- Introduce shared helper for activation toggling to avoid duplicated code.
- Introduce a generic function: `reconcileBoolToggle(desired, current, activateFn, deactivateFn)`.

---
# End of Domain Method Plan
