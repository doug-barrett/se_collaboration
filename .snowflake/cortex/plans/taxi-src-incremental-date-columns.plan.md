---
name: "taxi src incremental date columns"
created: "2026-09-10T00:18:55.678Z"
status: pending
---

# TAXI\_SRC: incremental date columns

Goal: give every source table a usable incremental key so downstream stages can do real incremental loading, and add realistic business dates where they genuinely fit. This is the first deliberate divergence of `TAXI_SRC` from `NY_TAXI.BRONZE`.

## Context

Current state of the seven reference tables (verified in the live account):

| Table            | Existing date columns                                        |
| ---------------- | ------------------------------------------------------------ |
| `VENDOR`         | none (`VENDOR_ID`, `VENDOR_NAME`)                            |
| `VENDOR_DETAILS` | none (`VENDOR_ID`, `HQ_ADDRESS_DETAILS`, `PHONE`, `DRIVERS`) |
| `DRIVERS`        | `LICENSE_EXPIRY`, `HIRE_DATE`                                |
| `LOCATION`       | none                                                         |
| `PAYMENT_TYPE`   | none                                                         |
| `RATE_CODE`      | none                                                         |
| `CALENDAR`       | `CALENDAR_DATE` (is itself the date)                         |

`TRIPS` already has `LOAD_DATE` (business, the trip's logical day) and `LAST_MODIFIED_TS` (physical insert time), so it needs no new column.

No Coalesce package in packages/ imposes a naming convention for incremental keys, so naming is ours to choose. Confirmed decisions: `UPDATED_AT TIMESTAMP_NTZ` on every reference table, business dates added where realistic, and the loader churns a small subset of reference rows daily.

## 1. Columns to add

Additive `ALTER TABLE ... ADD COLUMN` only — no rebuilds, no drops.

| Table            | New column(s)                                                  |
| ---------------- | -------------------------------------------------------------- |
| `VENDOR`         | `LICENSE_ISSUED_DATE DATE`, `UPDATED_AT TIMESTAMP_NTZ(9)`      |
| `VENDOR_DETAILS` | `UPDATED_AT TIMESTAMP_NTZ(9)`                                  |
| `DRIVERS`        | `UPDATED_AT TIMESTAMP_NTZ(9)` (already has two business dates) |
| `LOCATION`       | `ZONE_EFFECTIVE_DATE DATE`, `UPDATED_AT TIMESTAMP_NTZ(9)`      |
| `PAYMENT_TYPE`   | `UPDATED_AT TIMESTAMP_NTZ(9)`                                  |
| `RATE_CODE`      | `TARIFF_EFFECTIVE_DATE DATE`, `UPDATED_AT TIMESTAMP_NTZ(9)`    |
| `CALENDAR`       | `UPDATED_AT TIMESTAMP_NTZ(9)`                                  |

### Business date derivation — deterministic, so reruns and rebuilds agree

All three are hash-derived from the natural key, never random, so the same key always yields the same date:

- **`VENDOR.LICENSE_ISSUED_DATE`** — a TLC vehicle-licence issue date spread over the last \~10 years: `DATEADD(day, -MOD(ABS(HASH(VENDOR_ID)), 3650), DATE '2026-01-01')`. Gives every vendor a plausible, stable licence date and a genuine business date to model a "vendor tenure" attribute from later.
- **`LOCATION.ZONE_EFFECTIVE_DATE`** — TLC zone boundaries change rarely, so this picks from a small set of real-ish redistricting dates (`2011-01-01`, `2015-07-01`, `2019-01-01`, `2023-06-01`) by `MOD(ABS(HASH(LOCATION_ID)), 4)`. Low cardinality on purpose: that is how slowly-changing geography actually behaves.
- **`RATE_CODE.TARIFF_EFFECTIVE_DATE`** — NYC fare tariffs change on announced dates, so each of the 7 rate codes gets a fixed date from a short list keyed on `RATE_CODE_ID` (e.g. `2018-01-01`, `2019-02-01`, `2022-12-19`, `2025-01-05`). Hand-mapped rather than hashed, because these are meant to look like real tariff revisions.

`PAYMENT_TYPE`, `CALENDAR` and `VENDOR_DETAILS` get no business date — there genuinely isn't one, which is exactly why they get `UPDATED_AT` instead.

## 2. Making `UPDATED_AT` behave like a real source CDC column

This is the part that decides whether incremental loading actually works, so it needs care.

### The trap in the current MERGE

The loader's `MERGE` statements today use a bare `WHEN MATCHED THEN UPDATE`, which touches every matched row on every run (the log shows `REFS_MERGED = 4731` each time). If `UPDATED_AT` were set in that branch, every reference row would look modified every single day and an incremental predicate would pull the whole table — the opposite of the goal.

So each `MERGE` gets a **conditional** matched branch:

```sql
WHEN MATCHED AND (
       t.VENDOR_NAME <> s.VENDOR_NAME                     -- genuine content change
    OR MOD(ABS(HASH(s.VENDOR_ID, :P_RUN_DATE)), 100) < 2   -- selected for churn (~2%)
     )
THEN UPDATE SET
       t.VENDOR_NAME = s.VENDOR_NAME,
       t.UPDATED_AT  = :v_updated_at
```

Two independent triggers: real content drift from `BRONZE` (normally none, since `BRONZE` is static), and the synthetic daily churn.

### Deterministic churn selection

`MOD(ABS(HASH(<key>, :P_RUN_DATE)), 100) < 2` picks \~2% of rows, chosen by key **and** run date. Consequences that matter:

- Different rows churn on different days, so `UPDATED_AT` spreads out realistically.
- Re-running the same date selects the **same** rows, so the rerun is idempotent.

Approximate daily deltas: `VENDOR` \~22 rows, `VENDOR_DETAILS` \~22, `DRIVERS` \~5, `LOCATION` \~5, `CALENDAR` \~40, `PAYMENT_TYPE`/`RATE_CODE` usually 0 (7 rows at 2% — they will churn only occasionally, which is correct for a code table).

### Deterministic timestamp value

`UPDATED_AT` is set to a value derived from the run date, **not** `CURRENT_TIMESTAMP()`:

```sql
v_updated_at := :P_RUN_DATE::TIMESTAMP_NTZ + INTERVAL '6 hours';
```

`CURRENT_TIMESTAMP()` would move on every rerun, making the same logical day produce a different high-water mark each time. Anchoring to the run date keeps reruns byte-identical.

A guard `AND t.UPDATED_AT < :v_updated_at` is added to the churn condition so backfilling an **older** date can never drag a row's `UPDATED_AT` backwards.

### Churn is a touch, not a corruption

For `VENDOR`, `VENDOR_DETAILS`, `LOCATION`, `PAYMENT_TYPE`, `RATE_CODE` and `CALENDAR` the churn only bumps `UPDATED_AT`; the business columns keep matching `BRONZE` exactly. That preserves the existing verification check that `TAXI_SRC` reference content equals `BRONZE`.

The one genuine value change: **`DRIVERS.RATING` drifts** by ±0.1 (clamped to 1.0–5.0) on churned rows. Driver ratings really do move daily, it gives the future dimension something to track as a slowly-changing attribute, and it is a single well-understood column. Note the consequence: `DRIVERS.RATING` will no longer match `BRONZE`, so any future value-level recon on that column must exclude it. Row counts stay identical.

## 3. One-time backfill for data already loaded

14 days of trips and all seven reference tables are already populated, so the new columns land as `NULL`. A single additive `UPDATE` per table seeds them:

- Business dates set from the deterministic expressions in section 1.
- `UPDATED_AT` seeded to `2026-08-27 06:00` (the first backfilled load date), so the whole existing population shares a sensible starting high-water mark.

This is an additive backfill of brand-new columns, not a corrective rewrite — no truncate, no delete, no row loss. It runs exactly once.

Optionally, replaying `LOAD_DAILY_TAXI` across `2026-08-27..2026-09-09` afterwards will layer 14 days of realistic churn history onto `UPDATED_AT` (the trip guard skips the trip load, but the reference `MERGE` block still runs). Worth doing so freshness monitors and incremental predicates have a believable spread rather than one flat timestamp. I'll ask before running it.

## 4. Consistency question on `TRIPS`

`TRIPS.LAST_MODIFIED_TS` already plays the `UPDATED_AT` role. Renaming it to `UPDATED_AT` would give a single uniform incremental key name across all eight source tables, which makes the stage templates and Synq freshness monitors simpler and more predictable.

Recommendation: rename it. It is cheap right now — nothing downstream is built yet and the data is synthetic. `LOAD_DATE` stays as-is, since it is the trip's business date, not an audit column. I'll confirm before doing this, since it is the one change that touches an existing column rather than adding one.

## 5. Verification

1. **Schema divergence is exactly as intended** — diff `TAXI_SRC` against `BRONZE` and confirm the only differences are the 10 new columns listed in section 1. The existing phase-1 check expected a zero diff; it now expects this specific, documented delta.
2. **No NULLs left** — every reference row has a non-null `UPDATED_AT`, and every business date column is fully populated.
3. **Business dates are deterministic** — re-evaluate the derivation expressions and confirm they reproduce the stored values exactly; confirm `RATE_CODE` has its 7 hand-mapped dates and `LOCATION` only the 4 expected distinct values.
4. **Churn rate is in range** — after a replay, `COUNT(*) GROUP BY UPDATED_AT` shows roughly 2% of rows per date rather than 100% or 0%.
5. **Incremental predicate actually selects rows** — for a representative table, run `WHERE UPDATED_AT > <prior day 06:00>` and confirm it returns a small non-zero count, not the whole table and not nothing.
6. **Rerun idempotency holds** — call the loader twice for the same date; `UPDATED_AT` values are unchanged on the second call, reference row counts unchanged, trips still skipped.
7. **Backfill of an older date does not regress** — call the loader for a date earlier than an already-churned one and confirm no `UPDATED_AT` moves backwards.
8. **Reference content still matches `BRONZE`** — row-for-row equality on all columns except `DRIVERS.RATING` and the new columns.

## Critical files

- snowflake\_objects.sql - source DDL and `LOAD_DAILY_TAXI`; all seven `MERGE` statements change to conditional matched branches
- workspace.yml - `BRONZE` -> `SWALKER_DB_DEV.TAXI_SRC` mapping (unchanged, listed for orientation)

## Open items

- Confirm the `TRIPS.LAST_MODIFIED_TS` -> `UPDATED_AT` rename (section 4).
- Confirm whether to replay the 14-day churn history after seeding (section 3).
