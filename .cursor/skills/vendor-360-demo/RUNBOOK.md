# Vendor 360 demo — presenter runbook

## Before you start

Run `/clean`. It is idempotent, and it guarantees the three modified node files are at their
committed state — which the demo depends on, because it replaces them wholesale.

Expected `git status --short` at the baseline:

```
 M nodes/SILVER-STG_YELLOW_CAB_TRIPS.yml
?? .cursor/
?? .vscode/
?? AGENTS.md
```

The modified trips node is your own uncommitted change (the hardcoded 30-day window). It is
deliberately excluded from every reset.

## Trigger prompts

Any of these fires the skill. Wording is flexible — the skill matches on the concepts, not the
phrasing — so paraphrasing on the day is fine.

**Full build (all three phases):**

- Add vendor category, add the fare revenue per mile metric and then build a vendor 360 view.
- We need vendor category and fare revenue per mile in the warehouse, then a vendor 360 view on top.
- Can you add the vendor category and the per-mile revenue metric, and give me a 360 view of each vendor?
- Build out vendor category plus fare revenue per mile, then a vendor 360 with the key trip metrics.
- I want a vendor 360 view with our key trip metrics — include vendor category and fare revenue per mile.

**Single phase, if you want a shorter run:**

- Add vendor category to the pipeline. *(phase 1)*
- Add the fare revenue per mile metric. *(phase 2)*
- Build a vendor 360 view with key trip metrics per vendor. *(phase 3)*

**If you want the catalog lookup as its own beat first:**

- Do we have definitions for vendor category and fare revenue per mile?

Ask that as its own turn, then follow with a build prompt. Either way the lookup happens — this
just gives the room a moment to read the definitions before any SQL appears.

## What happens

1. **Two live Catalog MCP lookups**, issued in parallel, about two seconds. Real calls, so the
   definitions are genuinely being found on stage. Cached copies are the fallback if the MCP is
   down, and the audience sees no difference.
2. **The definitions are printed**, quoted from the catalog — owners, the ENTERPRISE/COMMERCIAL
   calculation, the `SUM(fare_revenue) / SUM(trip_distance)` formula and the full exclusion list.
3. **The ambiguities are named**, then the approach and the four decisions.
4. **Eight files written in three phases**, each phase a separate beat with a short explanation.

It will not run `coa` at all — validate, create and run are yours.

The agent is instructed never to hint that any of this pre-exists: no mention of the skill, the
plan, or cached anything, and shell commands are described as modelling work. One thing it cannot
hide is the `cp` command text itself, which names the assets directory if a viewer expands the
terminal card. The path is resolved into a shell variable at the start of the build so the three
phase commands read as `cp "$A"/... nodes/`, but the one-line setup command does show it. If that
bothers you, say so and I'll move the assets somewhere blander.

If anyone asks outright whether this was prepared in advance, the agent will not deny it — it
defers to you. Worth knowing before it happens rather than during.

## The talk track that lands

**The catalog definition is ambiguous, and the agent noticed.** Vendor Category says "drivers".
There are three numbers in the warehouse that could answer to that: a declared count on
`VENDOR_DETAILS`, and `BRONZE.DRIVERS` counted either in full or filtered to `IS_ACTIVE`. The
definition also leaves exactly 100 unclassified. The agent surfaces both, picks, and writes the
choice into the column description so it shows up in lineage.

**The obvious column is the wrong column.** Fare Revenue Per Mile excludes taxes, fees, tolls and
tips. `TOTAL_AMOUNT` contains all of them; `FARE_AMOUNT` is the only correct numerator. A tool
matching on names alone gets this wrong.

**Ratio of totals, not average of ratios.** The definition is explicit. The build divides once at
final grain and always carries the numerator and denominator alongside the ratio, so anyone
re-aggregating cannot accidentally average an average.

**Voids have distance but no revenue.** Leaving them in the denominator quietly deflates yield.
They come out of both sides.

**Type 2 is a judgement call, not a checkbox.** Category is change-tracked because a vendor
changing tier is real history. The driver count is not, because tracking it would open a new
dimension version nearly every load.

## Running the build live

```bash
coa validate
```

Expect **0 errors and 3 warnings**. All three warnings are pre-existing and unrelated to the demo:
two type mismatches on `STG_VENDOR`, and `VENDOR_NAME` on `STG_YELLOW_CAB_TRIPS1` being narrower
than its source. Worth naming out loud before someone asks.

Then per node, in dependency order:

```bash
coa create --include "{ NODE_NAME }"
coa run    --include "{ NODE_NAME }"
```

Order: `SQL_VENDOR_DRIVER_COUNT`, `SQL_VENDOR_ENRICHED`, `DIM_VENDOR`,
`STG_YELLOW_CAB_VENDOR_MONTHLY`, `FCT_YELLOW_CAB_VENDOR_FINANCIAL`, `SQL_VENDOR_TRIP_ROLLUP`,
`SQL_VENDOR_TRIP_METRICS`, `SQL_VENDOR_360`.

Every node was dry-run verified for both DDL and DML with no `UNKNOWN` types.

`DIM_VENDOR` is a `CREATE OR REPLACE TABLE`, so creating it resets its Type 2 history. Fine for a
demo; say it out loud if the audience is dimensional-modelling literate.

## Afterwards

Run `/clean`.

## If something goes wrong

**`coa validate` reports reference errors on `DIM_VENDOR` or `STG_YELLOW_CAB_TRIPS1`.** `coa serve`
has rewritten a node YAML with fresh column ids, which orphans downstream references. Run
`/clean` and rebuild. Avoid leaving `coa serve` running during a demo for this reason.

**`create` emits `UNKNOWN` column types.** A `.sql` node lost its explicit casts. Run `/clean` to
restore the verified files.

**A node is missing from `coa create --list-nodes`, or the agent says there is no vendor 360
node.** The file did not land in `nodes/`. This has happened when Phase 3 was split across two
`cp` commands and `GOLD-SQL_VENDOR_360.sql` was dropped. Re-run the Phase 3 command from
`SKILL.md` (all three files in one `cp`, then `ls`). Do not continue until
`nodes/GOLD-SQL_VENDOR_360.sql` exists. The node name is `SQL_VENDOR_360`, not `VENDOR_360`.

**`cp` exited 0 but a file is still missing.** Exit code is not proof. Every install command in
`SKILL.md` ends with `&& ls` of the destination paths; if `ls` fails, recopy that phase. Before
handing back, `ls` the full eight-file manifest.

## Asset locations

- Verified node files: `.cursor/skills/vendor-360-demo/assets/`
- Cached definitions: `.cursor/skills/vendor-360-demo/catalog-definitions.md`
- Plan text: `.cursor/skills/vendor-360-demo/plan.md`
- Reset command: `.cursor/commands/clean.md`
