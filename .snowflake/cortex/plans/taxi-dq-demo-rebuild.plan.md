---
name: "taxi dq demo rebuild"
created: "2026-09-09T23:35:43.795Z"
status: pending
---

# NY Taxi Data-Quality Demo — Rebuild Plan

Goal: a self-feeding demo where a daily Snowflake load lands taxi source data with deliberately planted defects, kicks off the Coalesce pipeline, and a known, repeatable subset of Synq tests / monitors / reconciliations fails while everything else stays green.

## What exists today (verified)

- `NY_TAXI.BRONZE` — 9 tables + 2 views. `CAB_TRIPS` and `YELLOW_CAB_TRIPS` are **views** holding a rolling \~7 days (948,450 rows, `2026-09-02` → `2026-09-08`). Reference tables: `VENDOR` (1,101), `VENDOR_DETAILS` (1,101, with an OBJECT column), `DRIVERS` (250), `LOCATION` (265), `PAYMENT_TYPE` (7), `RATE_CODE` (7), `CALENDAR` (2,000), `ZIP_CODES` (34,047), `TLC_ZONE_H3` (265).
- Repo `nodes/` has 14 leftover files (BRONZE sources + a partial vendor star). Workspace locations currently map `SILVER`/`GOLD`/`ICEBERG` at `SWALKER_DB_DEV.SILVER` etc.
- `apac-demo/snowflake_objects.sql` is the proven template: `GENERATE_DAILY_TRADES` (SQL proc, planted defects, `SYSTEM$SEND_EMAIL`), `TRIGGER_COALESCE_JOB` (Python proc, external access integration + secret, polls `runStatus`), and a two-task chain.
- `NZSF_EMAIL_ALERTS` notification integration already exists with `ALLOWED_RECIPIENTS = ('scott.walker@coalesce.io')` — **reuse it**, no new integration.

## Decisions taken

- Sources land in **`SWALKER_DB_DEV.TAXI_SRC`**; procs/tasks/log live in **`SWALKER_DB_DEV.TAXI_OPS`**.
- Volume-monitor failure comes from a **buggy `WHERE` clause in a stage node**, not a partial source load. Source volume stays steady so the story is clearly "the transform ate rows", not "the source was late".
- The Coalesce trigger proc gets built now but with **no job ID wired** — jobs get rebuilt during the pipeline phase.

## 1. Wipe and remap

- Delete all 14 files in `nodes/`. Keep `nodeTypes/`, `packages/`, `macros/`.

- Delete `jobs/*.yml` (all five are stale selectors over locations that won't exist).

- Remap `workspace.yml` and `environments/Production-18.yml` to new, dedicated schemas so we never overwrite anything currently in `SWALKER_DB_DEV.SILVER` / `.GOLD`:

  | Location   | Workspace (dev)              | Production (18)              |
  | ---------- | ---------------------------- | ---------------------------- |
  | `TAXI_SRC` | `SWALKER_DB_DEV.TAXI_SRC`    | `SWALKER_DB_DEV.TAXI_SRC`    |
  | `SILVER`   | `SWALKER_DB_DEV.TAXI_SILVER` | `SWALKER_DB_DEV.TAXI_SILVER` |
  | `GOLD`     | `SWALKER_DB_DEV.TAXI_GOLD`   | `SWALKER_DB_DEV.TAXI_GOLD`   |

  `BRONZE` mapping is retired — the pipeline now reads `TAXI_SRC`, not `NY_TAXI.BRONZE`. `NY_TAXI.BRONZE` stays untouched as the seed for the daily loader.

## 2. Source tables in `TAXI_SRC` — identical schemas

Created with `CREATE TABLE ... LIKE NY_TAXI.BRONZE.<t>` so column names, types and order match exactly (no `CTAS`, which would collapse `NUMBER(4,0)` etc.):

- `VENDOR`, `VENDOR_DETAILS`, `DRIVERS`, `LOCATION`, `PAYMENT_TYPE`, `RATE_CODE`, `CALENDAR` — small reference tables, **full refresh** each day.
- `TRIPS` — `LIKE NY_TAXI.BRONZE.CAB_TRIPS` (the view's shape: 24 columns), plus two appended audit columns `LOAD_DATE DATE` and `LAST_MODIFIED_TS TIMESTAMP_NTZ` so Synq freshness and volume monitors have something to key on. **Append-only** each day.

`TAXI_OPS.LOAD_LOG` records `RUN_DATE`, `STATUS`, per-table row counts, planted-defect counts, and `RUN_TS` — used later to prove which day each failure came from.

## 3. `TAXI_OPS.LOAD_DAILY_TAXI(P_RUN_DATE DATE)` — the daily loader

Modelled on `GENERATE_DAILY_TRADES`: SQL proc, `EXECUTE AS OWNER`, inner `BEGIN…EXCEPTION` so a failure still logs and emails. Colon-prefixed variable references throughout.

**Reference refresh** — truncate + insert each reference table from `NY_TAXI.BRONZE`. These are stable, so all reference-side tests pass every day.

**Trip sample** — pull a deterministic per-day slice of the `CAB_TRIPS` view and re-stamp it onto `P_RUN_DATE`:

- Pick the source day as `MIN_PU + MOD(DATEDIFF(day, anchor, :P_RUN_DATE), 7)` so the sample rotates through the 7 available days and keeps its natural intra-day shape.
- `SAMPLE` down to a **tight target of \~12,000–12,400 rows** (±2%), so the source volume monitor stays calm and the only volume anomaly is the one we engineer downstream.
- Shift `PICKUP_DATETIME` / `DROPOFF_DATETIME` onto `:P_RUN_DATE` preserving time-of-day; set `LOAD_DATE = :P_RUN_DATE`, `LAST_MODIFIED_TS = CURRENT_TIMESTAMP()`.
- `TRIP_ID` regenerated as a date-prefixed sequence so it's unique across days.

**Planted defect A — NULL test failure (every day).** Insert 3–6 extra trips with `PU_LOCATION_ID = NULL`. Chosen because it's a join key that a `not_null` test catches immediately and that a real TLC feed genuinely does emit.

**Planted defect B — business-rule failure (every day).** Insert 4–8 trips where `TOTAL_AMOUNT` does **not** equal `FARE_AMOUNT + EXTRA + MTA_TAX + TIP_AMOUNT + TOLLS_AMOUNT + IMPROVEMENT_SURCHARGE + CONGESTION_SURCHARGE + AIRPORT_FEE + CBD_CONGESTION_FEE` (off by a random $3–$18). This is the business test: arithmetically consistent everywhere else, so a custom SQL test with a 1-cent tolerance flags exactly these rows. All other columns on these rows are clean so they don't trip the other tests as collateral.

Everything else in the sample is left **clean on purpose** — valid vendor/payment/rate-code IDs, positive distances and fares, non-null timestamps, dropoff after pickup — so the large set of passing tests genuinely passes rather than passing by luck.

**Email** — `SYSTEM$SEND_EMAIL('NZSF_EMAIL_ALERTS', 'scott.walker@coalesce.io', …)` with a subject of `Taxi Daily Load: SUCCESS|FAILED (<date>)` and a body summarising row counts and planted-defect counts. Wrapped in its own exception block so a mail failure never fails the load.

## 4. Coalesce trigger + task chain

- Reuse the existing `COALESCE_API_NETWORK_RULE` / `COALESCE_API_TOKEN` / `COALESCE_API_ACCESS` objects from `NZSF_TEST` if they're still valid; otherwise recreate them under `TAXI_OPS`. **I'll confirm the correct Coalesce app hostname with you before creating the network rule** — `apac-demo` used the AU region, which may not be right here.
- `TAXI_OPS.TRIGGER_COALESCE_JOB(P_ENVIRONMENT_ID VARCHAR, P_JOB_ID VARCHAR)` — same Python proc as `apac-demo`: `POST /scheduler/startRun`, poll `/scheduler/runStatus` every 15s up to 600s, return `SUCCESS` / `SUCCESS (with test failures)` / `FAILED` / `TIMEOUT`. **No default job ID** — signature stays parameterised and unwired.
- `TASK_LOAD_DAILY_TAXI` — `USING CRON 0 6 * * *` (timezone your call), calls `LOAD_DAILY_TAXI(CURRENT_DATE())`. **Resumed.**
- `TASK_RUN_TAXI_PIPELINE` — `AFTER TASK_LOAD_DAILY_TAXI`, calls `TRIGGER_COALESCE_JOB`. Created and left **suspended** until the job exists.

## 5. Staging layer (`SILVER`) — V2 SQL Stage nodes, one concern each

- `STG_TRIP_CAST` — type normalisation only: `FLOAT` → `NUMBER(9,2)` on money, `NUMBER(38,0)` on the ID columns, `TIMESTAMP_TZ` → `TIMESTAMP_NTZ`. No filtering.

- `STG_TRIP_DERIVED` — derived measures only: `TRIP_MINUTES`, `FARE_PER_MILE`, `TOTAL_COMPONENT_SUM` (the sum used by the business test), `IS_AIRPORT_TRIP`.

- **`STG_TRIP_FILTERED` — the deliberate bug.** Nominally "exclude voided and test trips", and it does correctly drop `TOTAL_AMOUNT <= 0`. But it also carries:

  ```sql
  AND NOT (PAYMENT_TYPE_ID = 2 AND DAYOFWEEKISO(CURRENT_DATE()) IN (2, 4))
  ```

  On Tuesdays and Thursdays this silently drops every cash trip — roughly 25–35% of the day's rows. It reads like a plausible copy-paste of a payment-type exclusion whose day-of-week guard was never meant to ship. This is what breaks the volume monitor on `STG_TRIP_FILTERED` / `FCT_TRIP` twice a week while the source volume monitor stays green.

- `STG_VENDOR`, `STG_DRIVER`, `STG_LOCATION`, `STG_PAYMENT_TYPE`, `STG_RATE_CODE`, `STG_DATE` — one stage per dimension, cleaning only (trim, upper-case codes, coalesce descriptions). `STG_VENDOR_DETAILS` flattens the `HQ_ADDRESS_DETAILS` OBJECT in its own node, kept separate from `STG_VENDOR`'s column work.

## 6. Dimensional model

Dimensions (V1 Dimension node type, `.yml`, business key set, rest of the config left for you in `coa serve`):

- `DIM_VENDOR` (BK `VENDOR_ID`, enriched from the flattened details stage)
- `DIM_DRIVER` (BK `DRIVER_ID`)
- `DIM_LOCATION` (BK `LOCATION_ID`)
- `DIM_PAYMENT_TYPE` (BK `PAYMENT_TYPE_ID`)
- `DIM_RATE_CODE` (BK `RATE_CODE_ID`)
- `DIM_DATE` (BK `CALENDAR_DATE`)

Fact (V1 Fact node type):

- `FCT_TRIP` — grain one trip, from `STG_TRIP_FILTERED`, joined to the dims for surrogate keys. Modelling logic only; every transformation already happened upstream.
- `GOLD` gets `RPT_DAILY_VENDOR_SUMMARY` — daily trips / revenue / avg fare per vendor, so the volume drop is visible in a reporting object too.

## 7. `synq_monitors.yml` — monitors and tests

Namespace `taxi-data-quality`, `defaults: severity: ERROR`, entity IDs in the `sf-fka56740::swalker_db_dev::<schema>::<table>` form.

**Monitors**

- `volume` + `freshness` (on `LAST_MODIFIED_TS`) on `taxi_src.trips` — both stay green.
- `volume` on `silver.stg_trip_cast` — green.
- **`volume` on `silver.stg_trip_filtered` and `gold.fct_trip`** — these are the ones that fire on Tue/Thu once a few days of history are in place.
- `freshness` on `gold.fct_trip` (`LOAD_DATE`) — green.
- `field_stats` on `stg_trip_cast` for `PAYMENT_TYPE_ID`, `PU_LOCATION_ID`, `TOTAL_AMOUNT`.

**Passing tests (\~14)** — `not_null` on `TRIP_ID`, `PICKUP_DATETIME`, `DROPOFF_DATETIME`, `VENDOR_ID`, `PAYMENT_TYPE_ID`, `RATE_CODE_ID`, `TOTAL_AMOUNT`, `LOAD_DATE`; `unique` on `TRIP_ID`; `unique` on each dimension business key; `accepted_values` on `PAYMENT_TYPE_ID` (1–6) and `RATE_CODE_ID` (1–6, 99); referential-integrity SQL tests from `FCT_TRIP` back to each dimension.

**Failing test 1 — the null test.** `not_null` on `PU_LOCATION_ID` on `stg_trip_cast`, `save_failures: true`. Fails every day on the 3–6 planted rows.

**Failing test 2 — the business test.** Custom SQL test on `stg_trip_derived`:

```sql
SELECT TRIP_ID, TOTAL_AMOUNT, TOTAL_COMPONENT_SUM,
       TOTAL_AMOUNT - TOTAL_COMPONENT_SUM AS VARIANCE
FROM SWALKER_DB_DEV.TAXI_SILVER.STG_TRIP_DERIVED
WHERE ABS(TOTAL_AMOUNT - TOTAL_COMPONENT_SUM) > 0.01
```

Fails every day on the 4–8 planted rows.

Note: `PU_LOCATION_ID` is placed on `stg_trip_cast` (before the filter) deliberately, so the null-test failure and the volume failure are independent stories and don't mask each other.

## 8. `synq_recon.yaml` — reconciliations

Namespace `taxi-pipeline-recon`, `mode: row_checksum`, `key_columns: [TRIP_ID]` (or the dimension BK).

**Passing**

- `src-to-stg-cast` — `TAXI_SRC.TRIPS` → `TAXI_SILVER.STG_TRIP_CAST` (pure cast, 1:1).
- `stg-cast-to-derived` — `STG_TRIP_CAST` → `STG_TRIP_DERIVED` (adds columns, no filter).
- `vendor-recon` — `TAXI_SRC.VENDOR` → `GOLD.DIM_VENDOR` on `VENDOR_ID`.
- `location-recon` — `TAXI_SRC.LOCATION` → `GOLD.DIM_LOCATION` on `LOCATION_ID`.
- `payment-type-recon` — `TAXI_SRC.PAYMENT_TYPE` → `GOLD.DIM_PAYMENT_TYPE`.
- `filtered-to-fct` — `STG_TRIP_FILTERED` → `FCT_TRIP` (both post-bug, so they agree).

**Failing**

- **`src-to-fct`** — `TAXI_SRC.TRIPS` (`where: TOTAL_AMOUNT > 0`) → `GOLD.FCT_TRIP`, end-to-end. Every cash trip dropped by `STG_TRIP_FILTERED` on Tue/Thu shows as source-only, so this recon fails with thousands of missing keys twice a week and passes the rest of the time. The passing `filtered-to-fct` recon sitting right next to it is what localises the loss to the staging layer.

## 9. Build and verification

Layer by layer, one node at a time — `coa create` then `coa run` per the project loop, `--dry-run` / `--verbose` first where the SQL is non-obvious.

1. Snowflake DDL: schemas, source tables, `LOAD_LOG`.
2. Create the procs; call `LOAD_DAILY_TAXI` manually to **backfill \~10 consecutive days**, including at least two Tuesdays and two Thursdays. Volume monitors need history before they can flag an anomaly.
3. Build `SILVER` stages, then dims, then `FCT_TRIP`, then `GOLD`.
4. Verify each planted defect with direct SQL: exact count of null `PU_LOCATION_ID`, exact count of fare-variance rows, and the row-count delta between `STG_TRIP_CAST` and `STG_TRIP_FILTERED` on a Tue/Thu vs a Monday.
5. Deploy `synq_monitors.yml` and `synq_recon.yaml`; confirm the pass/fail split is exactly the intended one — 1 null test failing, 1 business test failing, the rest green; 2 volume monitors flagging on Tue/Thu; 1 recon failing, 6 passing.
6. Resume `TASK_LOAD_DAILY_TAXI`; leave `TASK_RUN_TAXI_PIPELINE` suspended until the Coalesce job is rebuilt and its ID is wired in.

## Open items to confirm during the build

- Coalesce app hostname for this account (drives the network rule).
- Whether `COALESCE_API_TOKEN` in `NZSF_TEST` is still valid or needs re-creating.
- Cron timezone and warehouse for the tasks (`COMPUTE_WH` assumed).
