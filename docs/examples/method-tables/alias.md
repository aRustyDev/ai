# Method Plan: Alias Resource

## Overview
The Addy.io Alias entity is mutable. It supports creation, update of selected attributes, activation/deactivation, recipient attachment management, limiting replies/sends to attached recipients, and deletion. Additional endpoints enable restore/forget operations and bulk actions. For Terraform:
- Resource: `addy_alias`
- Data Sources:
  - `addy_alias` (single lookup) – optional, if users need to reference unmanaged alias.
  - `addy_aliases` (list) – inventory/filtering.
- Toggle endpoints (`active`, `attached_recipients_only`) realized as boolean attributes.
- Recipient assignment handled via initial creation or explicit update operation.

Bulk endpoints (activate/deactivate/recipients/etc. in batch) and restore/forget operations are deferred until base lifecycle stabilizes.

## OpenAPI Endpoints Used (Core + Toggles + Recipient Ops)
| Purpose | HTTP | Endpoint |
|---------|------|----------|
| List aliases | GET | /api/v1/aliases |
| Create alias | POST | /api/v1/aliases |
| Read single alias | GET | /api/v1/aliases/{id} |
| Update alias (description, from_name) | PATCH | /api/v1/aliases/{id} |
| Delete alias | DELETE | /api/v1/aliases/{id} |
| Restore deleted alias | PATCH | /api/v1/aliases/{id}/restore |
| Forget alias (special removal) | DELETE | /api/v1/aliases/{id}/forget |
| Activate alias | POST | /api/v1/active-aliases |
| Deactivate alias | DELETE | /api/v1/active-aliases/{id} |
| Limit recipients (attached only) | POST | /api/v1/attached-recipients-only |
| Disable limit | DELETE | /api/v1/attached-recipients-only/{id} |
| Update recipients (replace set) | POST | /api/v1/alias-recipients |
| Bulk actions (activate/deactivate/delete/etc.) | POST /api/v1/aliases/<action>/bulk | Deferred |

## Terraform Method Mapping
| Terraform Method | Backing Endpoints | Notes |
|------------------|-------------------|-------|
| Create | POST /aliases (+ optional POST /active-aliases, POST /attached-recipients-only, POST /alias-recipients) | Initial creation, then toggles and recipients reconciliation; final Read. |
| Read | GET /aliases/{id} | Canonical state retrieval; used after every mutation. |
| Update | PATCH /aliases/{id}; activation & recipient limit endpoints; POST /alias-recipients | Only description, from_name patchable. Recipients replaced via POST /alias-recipients. |
| Delete | DELETE /aliases/{id} | Standard removal. Forget/restore endpoints deferred (not typical Terraform lifecycle). |
| Data Source (List) | GET /aliases (with filters & pagination) | Supports filtering by active, deleted, search, domain, recipient, username. |
| Data Source (Single) | GET /aliases/{id} | Optional lookup if not Terraform-managed. |
| Deferred Operations | Restore, Forget, Bulk endpoints | Potential future extended lifecycle or specialized data sources. |

## Attribute Classification
| Attribute | Source | Terraform Classification | Reason |
|-----------|--------|--------------------------|--------|
| id | Response | Computed | Server UUID. |
| domain | Create body; response | Required + ForceNew | Not patchable; change implies new alias. |
| local_part | Create (when format=custom) | Conditional Required + ForceNew | Only present when format=custom; immutable after creation. |
| extension | Response (nullable) | Computed | Provided by server (often null). |
| format | Create body | Optional + ForceNew | Chosen at creation (random_characters, uuid, random_words, custom); cannot patch. |
| description | Create/PATCH | Optional | Mutable via PATCH. |
| from_name | Create/PATCH (nullable) | Optional | Mutable via PATCH. |
| active | Activation endpoints | Optional + Computed | Managed as toggle. |
| attached_recipients_only | Toggle endpoints | Optional + Computed | Managed as toggle. |
| recipient_ids (desired set) | Create body or update via POST /alias-recipients | Optional | User-managed set; replaced wholesale by update operation. |
| recipients (full objects) | Response array | Computed (Nested) | Detailed info for each attached recipient. |
| emails_forwarded | Response | Computed | Metrics. |
| emails_blocked | Response | Computed | Metrics. |
| emails_replied | Response | Computed | Metrics. |
| emails_sent | Response | Computed | Metrics. |
| last_forwarded | Response (nullable) | Computed (nullable) | Activity timestamps. |
| last_blocked | Response (nullable) | Computed (nullable) | Activity timestamps. |
| last_replied | Response (nullable) | Computed (nullable) | Activity timestamps. |
| last_sent | Response (nullable) | Computed (nullable) | Activity timestamps. |
| email | Response | Computed | Composed address local_part@domain. |
| attached_recipients_only (duplicate row for clarity) | Response/toggle | Optional + Computed | Same as above; value from server authoritative. |
| deleted_at | Response (nullable) | Computed | Null unless soft-deleted; restore/forget deferred. |
| created_at | Response | Computed | Timestamp. |
| updated_at | Response | Computed | Timestamp. |
| user_id | Response | Computed | Correlation/debug only. |

## ForceNew Criteria
- `domain` and `local_part` (when `format=custom`) and `format` itself are immutable after creation.
- If user attempts to change these in plan, Terraform will plan replacement (marked ForceNew).
- `recipient_ids` changes do NOT force replacement; handled via separate POST /alias-recipients update.

## Create Flow (Detailed)
1. Build request body:
   - Always: `domain`
   - Optional: `description`, `format`
   - If `format=custom`: include `local_part`
   - Optional initial `recipient_ids` (array) if user provides.
2. POST /api/v1/aliases.
3. Record returned `id` and state.
4. Reconcile toggles:
   - If desired `active != response.active` → POST /active-aliases or DELETE /active-aliases/{id}.
   - If desired `attached_recipients_only != response.attached_recipients_only` → POST /attached-recipients-only or DELETE /attached-recipients-only/{id}.
5. Recipients:
   - If desired `recipient_ids` differs from current set returned (or user did not set initially) → POST /alias-recipients with `alias_id`, `recipient_ids`.
6. Final GET /aliases/{id} to normalize state.

## Update Flow
1. PATCH-able fields: `description`, `from_name`.
2. If either changed → PATCH /aliases/{id} with changed subset only.
3. Reconcile toggles (active, attached_recipients_only) by comparing current vs desired.
4. Recipients:
   - If `recipient_ids` in plan differs from existing set → POST /alias-recipients (replace set).
5. Final Read: GET /aliases/{id}.

## Delete Flow
- DELETE /api/v1/aliases/{id}.
- Ignore 404 on repeated deletion attempts.
- Do NOT call restore/forget endpoints during standard Terraform destroy (non-standard semantics).

## Read Behavior
- Populate all computed attributes.
- Null handling for timestamps and optional fields.
- Derived alias email is used directly from response (`email`).
- Recipients nested block (simplify initially to: id, email, can_reply_send, should_encrypt, inline_encryption, protected_headers, email_verified_at, created_at, updated_at).

## Recipients Management Decision
- Maintain a simple attribute `recipient_ids` representing desired attached set.
- Replace actual recipients using POST /alias-recipients on creation or update if set differs.
- Do not attempt partial add/remove initially—treat as full replacement semantics (documented).

## Data Source (List) Behavior
- GET /api/v1/aliases with filters:
  - filter[deleted]: with | only
  - filter[active]: true | false
  - filter[search]
  - sort
  - page[number], page[size]
  - with=recipients
  - recipient, domain, username (filter by ID)
- Provide optional arguments matching API query parameters.
- Return a list (or set) of nested alias objects (lightweight subset for performance).

## Data Source (Single) (Optional)
- GET /api/v1/aliases/{id} for non-managed alias reference.
- Could expose more detail or re-use nested schema portion.

## Attribute Modeling Notes
- `format` + `local_part` interplay:
  - If user sets `format=custom` must supply `local_part`.
  - Otherwise disallow `local_part` (error diagnostic).
- Provide validation: format in [`random_characters`, `uuid`, `random_words`, `custom`].

## Error Handling Expectations
| Scenario | Status | Handling |
|----------|--------|----------|
| Create success | 201 | Parse body; proceed to toggles. |
| Update success | 200 | Parse; proceed toggles/recipients. |
| Delete success | 204 | Remove state. |
| Activation toggle success | 200 | Continue; re-read. |
| Recipients update success | 200 | Continue; re-read. |
| Validation error | 422 | Diagnostic with mapped meaning. |
| Not found | 404 | After create/update read: error if still absent; during refresh after manual deletion: plan will recreate if configured. |
| Rate limit | 429 | Retry with backoff. |
| Server error | 5xx | Diagnostic; abort operation. |

## Logging Plan
- Entry log per operation: `tflog.Debug` with `operation`, `alias_id` (when available), `endpoint`.
- After response: log `status_code` + high-level category (success/failure).
- If recipients updated: log count of recipients attached.
- Do not log raw Authorization header or API key.

## Testing Plan Outline
Unit (mock transport):
- Create alias with format=uuid (no local_part).
- Create alias with format=custom + local_part.
- Update description only.
- Toggle active from false → true.
- Toggle attached_recipients_only → true.
- Replace recipients set (initial empty → new set).
- Validation error (422) from missing domain.
- Rate limit scenario (429 then 200).
- ForceNew logic: change domain should result in replace.

Acceptance (TF_ACC):
- Create alias (format random_words).
- Update description.
- Toggle active off → on.
- Attach recipient IDs (after implementing recipient resource).
- Toggle attached_recipients_only.
- Destroy alias.

## Edge Cases & Notes
- `deleted_at` returned null unless deleted; restore/forget endpoints complicate lifecycle not typical for Terraform—defer modeling.
- When `format` not custom, server picks local_part; treat `local_part` as Computed in those cases.
- Recipients might need pre-verification; if API rejects unverified recipient ID, surface diagnostic clearly.
- Bulk operations intentionally deferred to avoid state explosion and complexity.
- If server returns recipients inline only when query `with=recipients` used: consider an attribute `include_recipients` to control retrieval in data source. Resource always re-fetches recipients to maintain consistency if managing them.

## Method Plan Table (Summary)
```
Method Plan (alias):
# Create: POST /api/v1/aliases -> body: domain, description?, format?, local_part?(if custom), recipient_ids?
# Read:   GET /api/v1/aliases/{id}
# Update: PATCH /api/v1/aliases/{id} (description, from_name), POST /alias-recipients (replace recipients set), activation/cap limits toggles
# Delete: DELETE /api/v1/aliases/{id}
# Toggle active: POST /active-aliases | DELETE /active-aliases/{id} => active (Optional+Computed)
# Toggle attached recipients only: POST /attached-recipients-only | DELETE /attached-recipients-only/{id} => attached_recipients_only (Optional+Computed)
# Recipients management: POST /alias-recipients (full replacement; alias_id + recipient_ids)
# Immutable (ForceNew): domain, format, local_part (if format=custom)
# Computed metrics: emails_forwarded, emails_blocked, emails_replied, emails_sent, last_* timestamps
# Deferred: restore, forget, bulk endpoints
```

## Next Steps After Alias Implementation
- Generalize toggle reconciliation helper (shared with domain).
- Implement Recipient resource before enabling richer recipient management in alias.
- Add validation to ensure `recipient_ids` reference existing recipient resources when used in Terraform.
- Optimize data source retrieval (conditionally fetch recipients only when requested).

---
# End of Alias Method Plan
