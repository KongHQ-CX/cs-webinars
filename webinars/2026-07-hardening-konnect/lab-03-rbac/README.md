# Lab 3 — RBAC via Konnect Teams API

**Controls:** #7 RBAC least privilege  
**Time:** ~8 min

## What you'll do
1. Generate a Personal Access Token in the Konnect UI.
2. Create a scoped team (Viewer on one control plane only).
3. Create a system account, generate an access token for it, assign it to
   the `kong-developer` team, and verify it cannot modify services or plugins.

## Steps

```bash
export KONNECT_PAT="<your-admin-PAT>"
export KONNECT_CONTROL_PLANE_ID="<cp-uuid>"
export SYSTEM_ACCOUNT_NAME="kong-developer-svc"

# 1. Create the scoped team
bash lab-03-rbac/01-create-team.sh

# 2. Assign the Viewer role to the specific CP only, create the system
#    account, generate its access token, and add it to the team
bash ROLE=Viewer lab-03-rbac/02-assign-roles.sh

# 3. Verify read-only access using the system account's generated token
bash lab-03-rbac/verify.sh
```

## Expected results
- Team is listed in `GET https://global.api.konghq.com/v3/teams`.
- System account has the `viewer` role scoped to `$KONNECT_CONTROL_PLANE_ID`
  only, via membership in the `kong-developer` team.
- The system account's generated token can `GET` services (200) but
  attempting `DELETE /core-entities/services/<id>` → **403 Forbidden**.

> **Note:** Teams, Users, and role assignments are org-level resources in Konnect's
> Identity Management API — they live under `global.api.konghq.com/v3`, not the
> region-scoped `<region>.api.konghq.com/v2` used for Control Planes and Vaults.
