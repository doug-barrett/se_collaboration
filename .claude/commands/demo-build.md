---
description: Build the NY Taxi SILVER+GOLD analytics pipeline live, node by node, following the pre-saved plan
argument-hint: [optional business prompt to narrate for the room — the plan in .claude/demo-plan.md is still what gets built]
---

The user may paste a natural-language business ask as `$ARGUMENTS` (e.g. "stage the reference data, build conformed dimensions, then a trips fact and monthly vendor rollups split into financial and operational views"). Use it as the framing/narration for whoever is watching — but the actual thing to build is `.claude/demo-plan.md`, which describes the pipeline this build produces (7 dependency-respecting layers, 16 nodes, exact joins/filters/derived columns/keys for each).

**Do not author the node files from scratch.** The 16 correct, validated files already exist in `.claude/demo-node-cache/` — copy them into `nodes/` instead of regenerating content. This is the whole point of the cache: authoring via the model is slow; a file copy is instant.

Steps:

1. Copy the 16 files from `.claude/demo-node-cache/` into `nodes/` **one at a time, in layer order, pausing ~3 seconds between each** — this is deliberate pacing so nodes visibly appear one by one for the audience, not a bulk copy:
   ```
   cd /path/to/repo   # the repo root
   for f in \
     SILVER-STG_VENDOR.sql SILVER-STG_LOCATION.sql SILVER-STG_PAYMENT_TYPE.sql SILVER-STG_RATE_CODE.sql SILVER-STG_YELLOW_CAB_TRIPS.sql \
     GOLD-DIM_VENDOR.yml GOLD-DIM_LOCATION.yml GOLD-DIM_PAYMENT_TYPE.yml GOLD-DIM_RATE_CODE.yml \
     SILVER-PICKUP_LOCATION.yml SILVER-DROPOFF_LOCATION.yml \
     SILVER-STG_YELLOW_CAB_TRIPS1.sql \
     GOLD-FCT_YELLOW_CAB_TRIPS.yml \
     SILVER-STG_YELLOW_CAB_VENDOR_MONTHLY.sql \
     GOLD-FCT_YELLOW_CAB_VENDOR_FINANCIAL.yml GOLD-FCT_YELLOW_CAB_VENDOR_OPS.yml; do
     cp ".claude/demo-node-cache/$f" "nodes/$f"
     echo "built: $f"
     sleep 3
   done
   ```
   This takes ~50 seconds — run it as a normal (foreground) Bash call. The pacing is for whoever's watching the file system / IDE, not for anything in the chat turn.
2. Confirm all 16 expected filenames now exist in `nodes/` (see the list in `.claude/demo-plan.md` / `.claude/commands/demo-reset.md` — note the 7 Stage nodes are `.sql` files, everything else is `.yml`).
3. **Do not run `coa create`, `coa run`, or `coa validate`.** The user runs those live themselves (terminal and/or the Coalesce desktop app) as part of the demo performance.
4. Do not `git add`/commit/push anything.

**Close with a short narrative summary** (1-2 sentences) connecting the result back to whatever `$ARGUMENTS` described, e.g. "Built the vendor, location, payment type, and rate code dimensions, staged and enriched the trip data, and produced the trips fact plus monthly financial and operational rollups by vendor." Keep it for the audience — don't dump file-copy mechanics into that summary.

If `.claude/demo-node-cache/` is missing or incomplete (fewer than 16 files, or a filename doesn't match what `demo-reset.md` expects), stop and say so rather than falling back to authoring from scratch — that mismatch means the cache is stale and needs to be rebuilt from validated content first.
