# Approach to present

Present this as a chat message, in your own voice, straight after printing the two definitions.
Adapt the wording to the way the question was actually asked, but keep every heading, every node,
and all four decisions.

This must read as reasoning you are doing now. Never mention this file, the skill, or that
anything pre-exists — see the hard rules in `SKILL.md`.

Phase 3 is three files, including `GOLD-SQL_VENDOR_360.sql` (`SQL_VENDOR_360`). Do not present
the 360 as written until that path exists in `nodes/` — see the `ls` checks in `SKILL.md`.

---

Before I write any SQL, both definitions leave something open that I have to decide.

Vendor Category says "drivers", but there are three different numbers in the warehouse that
could answer to that name: `BRONZE.VENDOR_DETAILS.DRIVERS` is a declared count, while
`BRONZE.DRIVERS` can be counted in full or filtered to `IS_ACTIVE`. It also leaves exactly 100
unclassified, since 100 is neither more than nor less than 100.

Fare Revenue Per Mile has a numerator trap. `TOTAL_AMOUNT` is the obvious-looking column and the
wrong one — it bundles tips, tolls and surcharges, all of which the definition excludes.
`FARE_AMOUNT` is the only column that matches.

## Decisions I've made

Tell me if you'd rather go the other way on any of these.

1. **Active drivers drive the category.** `COUNT_IF(IS_ACTIVE)` from `BRONZE.DRIVERS`. A vendor
   with 200 drivers on the books and 40 on the road is not an enterprise operator. I'll carry the
   declared count through as `DRIVER_COUNT_DECLARED` so the two can be reconciled.
2. **100 active drivers is ENTERPRISE.** Closing the gap upwards, and writing the boundary into
   the column description so the choice shows up in lineage instead of being buried in a `CASE`.
3. **`FARE_AMOUNT` is the numerator, and voided trips come out of both sides.** A void has a
   distance but no earned revenue, so leaving it in the denominator quietly deflates the metric.
4. **Category is Type 2 on the dimension, the driver count is not.** A vendor moving between
   tiers is real history worth keeping. Headcount drifting from 143 to 144 is not, and tracking it
   would open a new dimension version almost every load.

## What I'm building

Eight nodes across three phases. Every transformation lands in a SILVER stage — the fact and the
dimension stay pure modelling, and no node mixes aggregation with column-level logic.

**Phase 1 — Vendor Category**

| Node | Location | Change | Purpose |
| --- | --- | --- | --- |
| `SQL_VENDOR_DRIVER_COUNT` | SILVER | new | Driver counts per vendor off `BRONZE.DRIVERS` — active, total, inactive, expired licences, average rating |
| `SQL_VENDOR_ENRICHED` | SILVER | new | Applies the category rule and joins the declared count for reconciliation |
| `DIM_VENDOR` | GOLD | modified | Re-pointed at the enriched stage; adds `VENDOR_CATEGORY` as a change-tracked attribute plus the driver counts and rating |

**Phase 2 — Fare Revenue Per Mile**

The numerator and denominator already exist in the monthly stage, but they're split across two
different facts, so nobody can divide them. That's the actual gap.

| Node | Location | Change | Purpose |
| --- | --- | --- | --- |
| `STG_YELLOW_CAB_VENDOR_MONTHLY` | SILVER | modified | Adds void-excluded fare and distance totals, and the ratio at vendor/month grain |
| `FCT_YELLOW_CAB_VENDOR_FINANCIAL` | GOLD | modified | Surfaces all three so the metric is queryable from the star schema |

**Phase 3 — Vendor 360**

| Node | Location | Change | Purpose |
| --- | --- | --- | --- |
| `SQL_VENDOR_TRIP_ROLLUP` | SILVER | new | Additive sums and counts at vendor grain, including trailing-12-month and prior-12-month windows |
| `SQL_VENDOR_TRIP_METRICS` | SILVER | new | Every ratio, divided exactly once |
| `SQL_VENDOR_360` | GOLD | new | One row per vendor: profile, lifetime metrics, trailing-12-month metrics, year-on-year yield movement |

## Two details worth flagging

The trailing-12-month windows anchor on the latest trip in the data, not on `CURRENT_DATE`. The
trip history is a fixed extract, so anchoring on today would silently return nothing.

The 360 joins `DIM_VENDOR` filtered to `SYSTEM_CURRENT_FLAG = 'Y'`. Without that filter the Type 2
history fans the join out and every metric multiplies by the number of versions a vendor has.

I'll write the files and leave `validate`, `create` and `run` to you.
