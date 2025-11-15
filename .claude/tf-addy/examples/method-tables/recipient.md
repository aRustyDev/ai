# Method Plan: Recipient Resource

## Overview
Recipients represent destination email addresses to which aliases can forward. A recipient can have various security and capability toggles: encryption, inline encryption, protected headers, ability to reply/send, and optional public key assignment. For Terraform:

- Resource: `addy_recipient`
- Data Sources:
  - `addy_recipients` (list).
  - `addy_recipient` (single lookup) optional if referencing unmanaged recipients.
- Toggle endpoints (can_reply_send, should_encrypt, inline_encryption, protected_headers) modeled as boolean attributes.
- Public key management modeled via an optional (Sensitive) attribute (`public_key`).
- Email verification resend action is deferred (not modeled as attribute; potential future action resource or on-demand command).
- Attachments to aliases handled elsewhere (alias resource).

## OpenAPI Endpoints Used
| Purpose | HTTP | Endpoint |
|---------|------|----------|
| List recipients | GET | /api/v1/recipients |
| Create recipient | POST | /api/v1/recipients |
| Read single recipient | GET | /api/v1/recipients/{id} |
| Delete recipient | DELETE | /api/v1/recipients/{id} |
| Resend verification email | POST | /api/v1/recipients/email/resend |
| Add public key | PATCH | /api/v1/recipient-keys/{id} |
| Remove public key | DELETE | /api/v1/recipient-keys/{id} |
| Enable encryption | POST | /api/v1/encrypted-recipients |
| Disable encryption | DELETE | /api/v1/encrypted-recipients/{id} |
| Enable inline encryption | POST | /api/v1/inline-encrypted-recipients |
| Disable inline encryption | DELETE | /api/v1/inline-encrypted-recipients/{id} |
| Enable protected headers | POST | /api/v1/protected-headers-recipients |
| Disable protected headers | DELETE | /api/v1/protected-headers-recipients/{id} |
| Allow reply/send | POST | /api/v1/allowed-recipients |
| Disallow reply/send | DELETE | /api/v1/allowed-recipients/{id} |
| (Indirect) Public key + encryption interaction | PATCH + POST toggle endpoints | Sequence constraints |

## Terraform Method Mapping
| Terraform Method | Backing Endpoints | Notes |
|------------------|-------------------|-------|
| Create | POST /recipients (+ optional PATCH /recipient-keys/{id}, POST toggle endpoints) | Only `email` required initially. Public key and toggles applied after creation if desired. |
| Read | GET /recipients/{id} | Canonical state source; re-read after every mutation. |
| Update | Combination of toggle endpoints, key add/remove endpoints | No PATCH for core fields except public key. Diff toggles and apply minimal calls. |
| Delete | DELETE /recipients/{id} | Removes recipient entirely. |
| Data Source (List) | GET /recipients (filter[verified]) | Provide filtering attributes. |
| Data Source (Single) | GET /recipients/{id} | Optional; for unmanaged recipients reference. |
| Deferred Actions | Resend verification email | Not modeled as attribute; consider later (e.g., transient action resource). |

## Attribute Classification
| Attribute | Source | Terraform Classification | Reason |
|-----------|--------|--------------------------|--------|
| id | Response | Computed | Server-generated UUID. |
| email | Request body (create), response | Required + ForceNew | Immutable; no PATCH endpoint to change email. |
| can_reply_send | Toggle endpoints | Optional + Computed | Managed via allow/disallow endpoints. |
| should_encrypt | Toggle endpoints, public key presence | Optional + Computed | Requires public key; encryption enabled/disabled via endpoints. |
| inline_encryption | Toggle endpoints | Optional + Computed | Depends on encryption; separate enable/disable endpoints. |
| protected_headers | Toggle endpoints | Optional + Computed | Independent toggle; hides subject line. |
| public_key | PATCH /recipient-keys/{id}, DELETE /recipient-keys/{id} | Optional (Sensitive) | Adds/removes key; sets fingerprint indirectly. |
| fingerprint | Response (nullable) | Computed | Derived from public key. |
| email_verified_at | Response (nullable) | Computed | Verification timestamp. |
| aliases_count | Response | Computed | Statistic of attached aliases. |
| created_at | Response | Computed | Creation timestamp. |
| updated_at | Response | Computed | Last update timestamp. |
| user_id | Response | Computed | Correlation/debug only. |

## Additional Derived Behaviors
- Setting `public_key` initially without enabling `should_encrypt` may still set `should_encrypt=true` (API examples show patch returning `should_encrypt: true`). Clarify by empirical test; treat as server-controlled computed if mismatch occurs.
- Removing `public_key` (public_key set to null in config) triggers DELETE /recipient-keys/{id} and sets `fingerprint` null; may also force `should_encrypt=false` logically (verify server behavior).

## ForceNew Criteria
- `email` is immutable, so changing it in configuration triggers resource replacement.
- Other attributes are toggles; managed by Update method without requiring replacement.

## Toggle Endpoints Mapping (Attribute Reconciliation)
| Attribute | Enable Endpoint | Disable Endpoint |
|-----------|-----------------|------------------|
| can_reply_send | POST /allowed-recipients | DELETE /allowed-recipients/{id} |
| should_encrypt | POST /encrypted-recipients | DELETE /encrypted-recipients/{id} |
| inline_encryption | POST /inline-encrypted-recipients | DELETE /inline-encrypted-recipients/{id} |
| protected_headers | POST /protected-headers-recipients | DELETE /protected-headers-recipients/{id} |

Public key management:
- Add/Update: PATCH /recipient-keys/{id} with `key_data`.
- Remove: DELETE /recipient-keys/{id}`

## Create Flow (Detailed)
1. Build request body: `{ "email": <required> }`
2. POST /api/v1/recipients → capture `id`.
3. If `public_key` provided:
   - PATCH /recipient-keys/{id} (key_data).
4. For each toggle attribute desired true but false in response:
   - can_reply_send → POST /allowed-recipients
   - should_encrypt → (requires key) POST /encrypted-recipients
   - inline_encryption → POST /inline-encrypted-recipients
   - protected_headers → POST /protected-headers-recipients
5. For any toggle desired false but defaulted true (unlikely): call corresponding DELETE endpoints.
6. Final GET /recipients/{id} to normalize state.

## Update Flow
1. Diff plan vs current state:
   - If `public_key` changed from null → value: PATCH /recipient-keys/{id}.
   - If changed from value → null: DELETE /recipient-keys/{id}.
   - If value changed to a different key: PATCH /recipient-keys/{id} again (server updates fingerprint).
2. Toggle attributes:
   - For each: if desired != current → call enable or disable endpoint.
   - Encryption sequence:
     - If enabling `should_encrypt` and no `public_key` → diagnostic error (public_key must be set first).
     - If disabling encryption and inline_encryption is currently true → disable inline first to avoid inconsistent state (prevent server errors).
3. Final Read GET /recipients/{id}.

## Delete Flow
- DELETE /api/v1/recipients/{id}.
- Ignore 404 on repeated deletion attempts.
- No need to revert toggles before deletion.

## Read Behavior
- GET /recipients/{id}.
- Populate computed attributes; null for missing timestamps or fingerprint.
- Represent absent public key as `public_key = null` and `fingerprint = null`.
- Ensure toggles reflect server truth even if user omitted them (Optional+Computed semantics maintain last known server state).

## Data Source (List) Behavior
- GET /api/v1/recipients
- Optional argument: `filter_verified` (maps to `filter[verified]` true/false).
- Return list of recipient objects (subset: id, email, verified, alias count, encryption flags).
- Provide attribute to include detailed flags (always included initially).

## Data Source (Single) (Optional)
- Expose all recipient attributes similar to resource Read.
- Useful when referencing externally created recipients in alias resource without managing them.

## Attribute Interaction Rules
- `inline_encryption` should not be enabled unless `should_encrypt` is true (document; enforce precondition diagnostic).
- `protected_headers` likely requires encryption (verify; if so enforce).
- `can_reply_send` independent; can be enabled without encryption.

## Error Handling Expectations
| Scenario | Status | Handling |
|----------|--------|----------|
| Create success | 201 | Continue with toggles. |
| Toggle enable success | 200 | Continue. |
| Public key add success | 200 | Fingerprint set. |
| Delete success | 204 | Remove from state. |
| Validation error | 422 | Diagnostic with mapped meaning. |
| Not found | 404 | In Read after deletion—treat as gone; otherwise diagnostic. |
| Rate limit | 429 | Retry with backoff. |
| Server error | 5xx | Diagnostic; stop operation. |
| Encryption enable without key | Likely 4xx | Preempt with Terraform validation diagnostic. |

## Logging Plan
- Operation entry: `tflog.Debug` with `operation=Create|Update|Delete|Read`, `recipient_id` (if available).
- After each toggle/public key action: log action + endpoint + status_code.
- Avoid logging raw key material (`public_key`).

## Testing Plan Outline
Unit (mock transport):
- Create basic recipient (no toggles).
- Add public key on create; verify fingerprint set.
- Enable encryption after key; verify both flags.
- Attempt enable encryption without key (expect diagnostic).
- Enable inline encryption only after encryption (sequence).
- Disable protected headers.
- Replace public key (new fingerprint).
- Remove public key (fingerprint null, should_encrypt possibly false).
- Rate limit scenario (429 then 200).
- Validation error (422) for malformed email.

Acceptance (TF_ACC):
- Create recipient.
- Add public key.
- Enable encryption + inline + protected headers.
- Disable inline → disable protected headers → disable encryption.
- Remove public key.
- Destroy recipient.

## Edge Cases & Notes
- If API automatically sets `should_encrypt` when a key is added, treat attribute as Computed; user’s desired value should still reconcile (if user sets should_encrypt=false but key exists, may require DELETE /encrypted-recipients).
- Removing key while encryption enabled should implicitly disable encryption; verify behavior—may require explicit disable sequence before DELETE /recipient-keys/{id}.
- Resend verification email endpoint not integrated—could be introduced later via a data source “action” or a special attribute (not recommended).
- Ensure ordering: disable inline before disabling encryption to avoid API error states.
- Public key updates should not force replacement; treat changes as in-place.

## Method Plan Table (Summary)
```
Method Plan (recipient):
# Create: POST /api/v1/recipients -> body: email
# Post-Create: optional PATCH /recipient-keys/{id}; toggle endpoints for can_reply_send, should_encrypt, inline_encryption, protected_headers
# Read:   GET /api/v1/recipients/{id}
# Update: key changes via PATCH/DELETE recipient-keys/{id}; toggles via respective POST/DELETE endpoints
# Delete: DELETE /api/v1/recipients/{id}
# Encryption toggles require public key; inline_encryption requires should_encrypt=true
# Immutable (ForceNew): email
# Computed: fingerprint, timestamps, counts, user_id
# Deferred: resend verification email; complex dependency error modeling
```

## Next Steps After Recipient Implementation
- Integrate recipient IDs validation when used by alias resource (check existence via GET; optional pre-flight).
- Provide helper functions: `reconcileToggle(ctx, desired, current, enableFn, disableFn)` and `ensureEncryptionPrerequisites`.
- Consider adding a “verification_status” derived attribute (verified vs unverified) for improved ergonomics.

---
# End of Recipient Method Plan
