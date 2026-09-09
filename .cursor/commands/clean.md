Reset this repo to its pre-demo baseline by removing everything the vendor-360 demo installs
locally. Nothing in Snowflake needs cleaning up — every node is `CREATE OR REPLACE`, so the next
run overwrites in place.

Run exactly this, from the repo root:

```bash
rm -f nodes/SILVER-SQL_VENDOR_DRIVER_COUNT.sql \
      nodes/SILVER-SQL_VENDOR_ENRICHED.sql \
      nodes/SILVER-SQL_VENDOR_TRIP_ROLLUP.sql \
      nodes/SILVER-SQL_VENDOR_TRIP_METRICS.sql \
      nodes/GOLD-SQL_VENDOR_360.sql

git checkout -- nodes/GOLD-DIM_VENDOR.yml \
                nodes/SILVER-STG_YELLOW_CAB_VENDOR_MONTHLY.yml \
                nodes/GOLD-FCT_YELLOW_CAB_VENDOR_FINANCIAL.yml

git status --short
```

Both commands are safe to run when there is nothing to clean, so `/clean` is idempotent and can be
run before a demo as well as after.

## Do not

- Do not run `git reset`, `git stash`, `git clean`, or `git checkout -- .`. Restore only the three
  paths listed above.
- Do not touch `nodes/SILVER-STG_YELLOW_CAB_TRIPS.yml`. Its uncommitted change is deliberate and
  must survive every reset.
- Do not touch `AGENTS.md`, `.vscode/`, `.cursor/`, or anything under `nodeTypes/`.
- Do not run any `coa` command. No deploy, no refresh, no Snowflake cleanup.

## Then report

Confirm in one or two lines that the eight demo files are gone and the repo is ready for another
run. Expected `git status --short` afterwards is the untracked `.cursor/`, `.vscode/` and
`AGENTS.md`, plus the modified `nodes/SILVER-STG_YELLOW_CAB_TRIPS.yml`.

If anything else shows as modified, say so rather than fixing it — most likely `coa serve`
rewrote a node file and it needs a decision.
