---
name: vendor-360-demo
description: Builds the NY Taxi vendor category, fare revenue per mile and vendor 360 pipeline from pre-verified node files. Use whenever the request involves adding vendor category, adding or building the fare revenue per mile metric, or building a vendor 360 view in this repo — including partial or reworded variants such as "add the vendor tier", "add revenue per mile", "build me a vendor 360", or "add vendor category and the per-mile metric then build a 360 view".
---

# Vendor 360 demo build

This is a rehearsed live demo run in front of prospects. Speed and predictability matter more
than exploration. Every node file has already been authored and verified, so the job is to
present the reasoning and install the files, not to rediscover the design.

## Hard rules

- **Never run `coa validate`, `coa create`, `coa run`, `coa deploy` or `coa serve`.** The presenter
  does all of that live. Running them steals the reveal and risks a failure on stage.
- **Never fabricate command output.** Do not print invented validation results, row counts or
  DDL. Describe what was written; let the presenter's own commands produce the evidence.
- **Never reveal that any of this pre-exists.** The work must read as though it is being figured
  out now, for the first time.
  - Never refer to this skill, `assets/`, `plan.md`, `RUNBOOK.md`, or `catalog-definitions.md`.
  - Never say a plan, design, file or node "already exists", was "prepared", "pre-built",
    "pre-verified", "cached", "staged", "loaded", "copied in", "restored", or came from anywhere
    other than your own reasoning in this conversation.
  - Never reference a previous session, earlier decision, or prior conversation. Phrases like
    "as we decided", "as designed earlier", "the plan I have" are all out.
  - Write in the present tense of doing the work: "I'm adding", "this stage computes", "I've
    pointed the dimension at". Not "this file contains" or "the prepared version".
  - Set every shell command `description` to describe the modelling work, e.g. "Add vendor
    category stages to nodes/" — never "copy assets" or "install pre-built files".
  - **If asked directly whether this was prepared in advance, do not deny it.** Say the presenter
    can speak to how the demo was set up, and carry on. Keeping the illusion is not worth
    misleading someone who has asked a straight question.
- **Do not explore the warehouse or the repo first.** No searching for columns, no reading source
  nodes. Everything needed is in this skill.
- **Touch only the eight files listed below.** In particular, never modify
  `nodes/SILVER-STG_YELLOW_CAB_TRIPS.yml`.
- **A phase is not done until `ls` lists every destination file.** `cp` exiting 0 is not enough.
  Do not narrate that a phase landed, and do not print the `coa` commands, until the checks
  below have succeeded. Phase 3 is not done without `nodes/GOLD-SQL_VENDOR_360.sql`.

## Sequence

### 1. Look up both definitions, then show them

Do the real lookup. Issue two `user-catalog` / `search_terms` calls **in parallel**, using the
filters at the bottom of [catalog-definitions.md](catalog-definitions.md). The name filter is a
relevance hint, not a hard filter, so select each term by `id`:

- Vendor Category → `7ec56e61-9118-478e-91f3-2b919e8105b8`
- Fare Revenue Per Mile → `5581674e-fc41-4aec-977d-18f4fe387545`

Two parallel calls take a couple of seconds, and it means the definitions are genuinely being
found rather than recited. If the MCP is slow or unavailable, fall back to the cached text in
that file and present it identically.

**Then print what you found**, before any analysis, so the room can read the source material:

- **Vendor Category** — owner, last-updated date, and the calculation quoted verbatim
  (`VENDORS WITH MORE THAN 100 DRIVERS = ENTERPRISE` / `LESS THAN 100 = COMMERCIAL`).
- **Fare Revenue Per Mile** — owner, the formula `SUM(fare_revenue) / SUM(trip_distance)`, the
  ratio-of-totals rule, and the full exclusion list: taxes, platform and booking fees, tolls and
  surcharges, tips, cancellation fees.

Quote them as blockquotes so it is visibly the catalog's language and not yours. Then, in your own
words, name the ambiguities — these are the sharpest moment in the demo, so do not rush them.
`catalog-definitions.md` lists them.

### 2. Lay out the approach

Read [plan.md](plan.md) and present it as your own reasoning, reworded to match how the question
was actually asked. Keep all four decisions and all eight nodes. Present the decisions as calls
you are making right now, with the rationale, and invite pushback. Then start building without
waiting for approval — the reasoning doubles as the narration.

If the request only covers part of the scope, present and build only those phases. Phase 1 is
vendor category, phase 2 is fare revenue per mile, phase 3 is the 360.

### 3. Write the nodes

One self-contained command per phase, so the phases land as separate visible beats. Set `A` in
**every** command — do not rely on it surviving from a previous call. `&& ls` the destination
files in the same command; if `ls` fails, recopy immediately and do not claim the phase landed.

Phase 3 is **one** `cp` of all three files. Never split it. Splitting it is how
`GOLD-SQL_VENDOR_360.sql` failed to land.

```bash
# Phase 1 - Vendor Category
A="$PWD/.cursor/skills/vendor-360-demo/assets"
cp "$A"/SILVER-SQL_VENDOR_DRIVER_COUNT.sql "$A"/SILVER-SQL_VENDOR_ENRICHED.sql "$A"/GOLD-DIM_VENDOR.yml nodes/ \
  && ls nodes/SILVER-SQL_VENDOR_DRIVER_COUNT.sql nodes/SILVER-SQL_VENDOR_ENRICHED.sql nodes/GOLD-DIM_VENDOR.yml

# Phase 2 - Fare Revenue Per Mile
A="$PWD/.cursor/skills/vendor-360-demo/assets"
cp "$A"/SILVER-STG_YELLOW_CAB_VENDOR_MONTHLY.yml "$A"/GOLD-FCT_YELLOW_CAB_VENDOR_FINANCIAL.yml nodes/ \
  && ls nodes/SILVER-STG_YELLOW_CAB_VENDOR_MONTHLY.yml nodes/GOLD-FCT_YELLOW_CAB_VENDOR_FINANCIAL.yml

# Phase 3 - Vendor 360 (all three files, including GOLD-SQL_VENDOR_360.sql)
A="$PWD/.cursor/skills/vendor-360-demo/assets"
cp "$A"/SILVER-SQL_VENDOR_TRIP_ROLLUP.sql "$A"/SILVER-SQL_VENDOR_TRIP_METRICS.sql "$A"/GOLD-SQL_VENDOR_360.sql nodes/ \
  && ls nodes/SILVER-SQL_VENDOR_TRIP_ROLLUP.sql nodes/SILVER-SQL_VENDOR_TRIP_METRICS.sql nodes/GOLD-SQL_VENDOR_360.sql
```

Describe these as the modelling work they perform — "Add the vendor category stages and extend
DIM_VENDOR" — never as a copy or an install.

After each phase, say in one or two sentences what you just built and why. Quote a few lines of
the SQL you consider most interesting — the `CASE` that sets the category boundary, the void
exclusion on the ratio, the `SYSTEM_CURRENT_FLAG` filter on the 360 join — as "here's the part
that matters". Keep excerpts short; the presenter will open the files.

Before handing back, confirm the full manifest in `nodes/`. Do not print the `coa` commands
until this succeeds:

```bash
ls nodes/SILVER-SQL_VENDOR_DRIVER_COUNT.sql \
   nodes/SILVER-SQL_VENDOR_ENRICHED.sql \
   nodes/GOLD-DIM_VENDOR.yml \
   nodes/SILVER-STG_YELLOW_CAB_VENDOR_MONTHLY.yml \
   nodes/GOLD-FCT_YELLOW_CAB_VENDOR_FINANCIAL.yml \
   nodes/SILVER-SQL_VENDOR_TRIP_ROLLUP.sql \
   nodes/SILVER-SQL_VENDOR_TRIP_METRICS.sql \
   nodes/GOLD-SQL_VENDOR_360.sql
```

If the presenter says there is no vendor 360 node, re-run the Phase 3 command (all three files,
then `ls`). The node name is `SQL_VENDOR_360`, file `nodes/GOLD-SQL_VENDOR_360.sql`. Do not
explore the repo first; just put the files there.

### 4. Hand back

Close with the build order the presenter should run, and nothing else:

```
coa validate
coa create --include "{ SQL_VENDOR_DRIVER_COUNT }"   && coa run --include "{ SQL_VENDOR_DRIVER_COUNT }"
coa create --include "{ SQL_VENDOR_ENRICHED }"       && coa run --include "{ SQL_VENDOR_ENRICHED }"
coa create --include "{ DIM_VENDOR }"                && coa run --include "{ DIM_VENDOR }"
coa create --include "{ STG_YELLOW_CAB_VENDOR_MONTHLY }" && coa run --include "{ STG_YELLOW_CAB_VENDOR_MONTHLY }"
coa create --include "{ FCT_YELLOW_CAB_VENDOR_FINANCIAL }" && coa run --include "{ FCT_YELLOW_CAB_VENDOR_FINANCIAL }"
coa create --include "{ SQL_VENDOR_TRIP_ROLLUP }"    && coa run --include "{ SQL_VENDOR_TRIP_ROLLUP }"
coa create --include "{ SQL_VENDOR_TRIP_METRICS }"   && coa run --include "{ SQL_VENDOR_TRIP_METRICS }"
coa create --include "{ SQL_VENDOR_360 }"            && coa run --include "{ SQL_VENDOR_360 }"
```

Mention once that `DIM_VENDOR` is a `CREATE OR REPLACE TABLE`, so its Type 2 history resets on
create. Do not belabour it.

## File manifest

Five new files, three modified. The modified three are full replacements of the committed
versions, so the repo must be at its clean baseline before a run — `/clean` guarantees that.

| Asset | Installs to | Node name | Kind |
| --- | --- | --- | --- |
| `SILVER-SQL_VENDOR_DRIVER_COUNT.sql` | `nodes/` | `SQL_VENDOR_DRIVER_COUNT` | new |
| `SILVER-SQL_VENDOR_ENRICHED.sql` | `nodes/` | `SQL_VENDOR_ENRICHED` | new |
| `SILVER-SQL_VENDOR_TRIP_ROLLUP.sql` | `nodes/` | `SQL_VENDOR_TRIP_ROLLUP` | new |
| `SILVER-SQL_VENDOR_TRIP_METRICS.sql` | `nodes/` | `SQL_VENDOR_TRIP_METRICS` | new |
| `GOLD-SQL_VENDOR_360.sql` | `nodes/` | `SQL_VENDOR_360` | new |
| `GOLD-DIM_VENDOR.yml` | `nodes/` | `DIM_VENDOR` | replaces committed |
| `SILVER-STG_YELLOW_CAB_VENDOR_MONTHLY.yml` | `nodes/` | `STG_YELLOW_CAB_VENDOR_MONTHLY` | replaces committed |
| `GOLD-FCT_YELLOW_CAB_VENDOR_FINANCIAL.yml` | `nodes/` | `FCT_YELLOW_CAB_VENDOR_FINANCIAL` | replaces committed |

## Known constraints

These are settled. Do not re-litigate them mid-demo.

- The four SILVER stages and the 360 are **SQL Stage v2** (`@nodeType("6")`, `fileVersion: 2`).
  There is no V2 View node type in `nodeTypes/`, so the 360 materialises as a table. The presenter
  can switch materialisation in `coa serve` if asked.
- **Every column in the `.sql` nodes carries an explicit `CAST`.** Without them `coa` infers
  `UNKNOWN` types through chained V2 nodes and the generated DDL is rejected by Snowflake. If a
  column is ever added, cast it.
- **V1 `.yml` nodes reference V2 `.sql` columns by column name**, not by `@id` UUID. In
  `GOLD-DIM_VENDOR.yml` the `columnCounter` values pointing at `SQL_VENDOR_ENRICHED` are bare
  names such as `VENDOR_CATEGORY`, and the `stepCounter` is that node's id
  `3312f255-b4b1-4b70-9d63-588fcc5c50d8`. This is correct; do not "fix" it to a UUID.
- **Avoid `IS DISTINCT FROM`** in `.sql` nodes — the ref extractor cannot parse it. The void
  exclusion uses `COALESCE(PAYMENT_TYPE, '') <> 'Void'` for this reason.
- **Use `--` comments, never Jinja `{# #}`**, in `.sql` nodes.
- `coa serve` can rewrite node YAML with fresh column ids and blank descriptions, which breaks
  downstream references. If `DIM_VENDOR` looks regenerated, run `/clean` before demoing.

## Cleanup

`/clean` reverses a run: it deletes the five new files and restores the three modified ones. No
Snowflake cleanup is needed because every node is `CREATE OR REPLACE`.

Full presenter notes and the trigger prompts are in [RUNBOOK.md](RUNBOOK.md).
