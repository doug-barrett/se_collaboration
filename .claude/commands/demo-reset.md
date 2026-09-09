---
description: Reset the NY Taxi demo canvas back to bronze-only, ready for the LLM to rebuild live with /demo-build
---

Reset this Coalesce project's canvas to bronze-only for a live demo. BRONZE source nodes must stay untouched; only the SILVER/GOLD analytics pipeline built on top of them gets cleared.

**Target nodes** (exactly these 16 files in `nodes/` — the taxi analytics pipeline):

```
nodes/SILVER-STG_VENDOR.sql
nodes/SILVER-STG_LOCATION.sql
nodes/SILVER-STG_PAYMENT_TYPE.sql
nodes/SILVER-STG_RATE_CODE.sql
nodes/SILVER-STG_YELLOW_CAB_TRIPS.sql
nodes/SILVER-PICKUP_LOCATION.yml
nodes/SILVER-DROPOFF_LOCATION.yml
nodes/SILVER-STG_YELLOW_CAB_TRIPS1.sql
nodes/SILVER-STG_YELLOW_CAB_VENDOR_MONTHLY.sql
nodes/GOLD-DIM_VENDOR.yml
nodes/GOLD-DIM_LOCATION.yml
nodes/GOLD-DIM_PAYMENT_TYPE.yml
nodes/GOLD-DIM_RATE_CODE.yml
nodes/GOLD-FCT_YELLOW_CAB_TRIPS.yml
nodes/GOLD-FCT_YELLOW_CAB_VENDOR_FINANCIAL.yml
nodes/GOLD-FCT_YELLOW_CAB_VENDOR_OPS.yml
```

Note the 7 Stage nodes are `.sql` files (V2 stage type, `@nodeType("6")`) — everything else (dimensions, views, facts) is `.yml`.

**Do NOT touch:** any `nodes/BRONZE-*.yml`, `nodes/SYNQ_AUDIT-SYNQ_AUDIT.yml`, `nodes/SILVER-STG_SYNQ_AUDIT.yml`, `nodes/SILVER-V_SYNQ_AUDIT.yml` (these are an audit/test-framework wired to a specific test ID, not part of the demo pipeline), `nodeTypes/`, `jobs/`, `subgraphs/`, `environments/`, `workspace.yml`, `.claude/demo-plan.md`, and — critically — **`.claude/demo-node-cache/`**. That cache is the source `/demo-build` pulls from; deleting it would break the next build. Only `nodes/` gets cleared.

Steps:

1. Delete the 16 target files from `nodes/` (leave `.claude/demo-node-cache/`'s copies untouched).
2. Do **not** run `coa create`/`coa run` to drop anything in the warehouse — the next `/demo-build` recreates everything with `CREATE OR REPLACE`, so there's nothing to clean up there. Do not `git add`/commit/push anything.
3. Report back concisely: how many files were removed, and that the canvas now shows bronze sources only, ready for `/demo-build`.
