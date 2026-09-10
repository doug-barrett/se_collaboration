---
name: "taxi dq demo phase1 data prep"
created: "2026-09-09T23:48:42.661Z"
status: pending
---

# NY Taxi DQ Demo — Phase 1: Data Prep

Scope is deliberately narrow: get the source tables and the daily loader right, verify the sample data, and stop. Nodes, dimensional model, tests, monitors and reconciliations are all deferred to later plans.

## Context

Verified against the live account (`fka56740`) and the repo:

- `NY_TAXI.BRONZE` has 9 real tables plus **2 views** — `CAB_TRIPS` and `YELLOW_CAB_TRIPS`. The `CAB_TRIPS` view holds a rolling \~7 days (948,450 rows, `2026-09-02` → `2026-09-08`, 24 columns). Views are not copied; they are only **read as a seed** by the loader.
- Reference tables: `VENDOR` (1,101), `VENDOR_DETAILS` (1,101, includes an `OBJECT` column `HQ_ADDRESS_DETAILS`), `DRIVERS` (250), `LOCATION` (265), `PAYMENT_TYPE` (7), `RATE_CODE` (7), `CALENDAR` (2,000), `ZIP_CODES` (34,047), `TLC_ZONE_H3` (265).
- Stale artefacts tied to the old pipeline: 14 files in nodes/, 5 in jobs/, 2 in subgraphs/ (`Customer-105.yml`, `NewSubgraph-118.yml`).
- `NZSF_EMAIL_ALERTS` notification integration already exists with `ALLOWED_RECIPIENTS = ('scott.walker@coalesce.io')` — reuse it, create nothing new.
- ../apac-demo/snowflake\_objects.sql is the working template for the proc / email / Python trigger / task-chain pattern.

## Ground rules carried into this plan

- **Delete only nodes/, jobs/ and subgraphs/** — all three reference nodes that are being rebuilt. nodeTypes/, packages/ and macros/ are kept and reused.
- **Never truncate.** Not for duplicates, not for reruns, not for anything. Idempotency comes from `MERGE` and from `WHERE NOT EXISTS` guards, so the Coalesce templates and Synq monitors keep intact history.
- **Sources are real tables**, loaded manually and incrementally by the proc. Nothing in the new pipeline reads a view.
- **The location is still called `BRONZE`**, just remapped to the new source schema.
- **No nodes get built** until the sample data is confirmed correct.

## 1. Repo cleanup and remapping

- Delete the 14 files in nodes/, the 5 in jobs/, and the 2 in subgraphs/.

- Keep nodeTypes/, packages/, macros/ untouched.

- Remap `BRONZE` in both workspace.yml and environments/Production-18.yml:

  | Location | Was              | Becomes                   |
  | -------- | ---------------- | ------------------------- |
  | `BRONZE` | `NY_TAXI.BRONZE` | `SWALKER_DB_DEV.TAXI_SRC` |

  `SILVER`, `GOLD`, `ICEBERG`, `SYNQ_AUDIT` mappings are left alone in this phase — they only matter once nodes exist, and I'd rather settle their targets in the modelling plan than churn them now.

## 2. Snowflake DDL — `TAXI_SRC` and `TAXI_OPS`

Two new schemas: `SWALKER_DB_DEV.TAXI_SRC` (sources) and `SWALKER_DB_DEV.TAXI_OPS` (proc, task, load log).

**Reference tables** — created with `CREATE TABLE ... LIKE NY_TAXI.BRONZE.<t>` so column names, types, order and precision match exactly (a `CTAS` would flatten `NUMBER(4,0)` and similar):

`VENDOR`, `VENDOR_DETAILS`, `DRIVERS`, `LOCATION`, `PAYMENT_TYPE`, `RATE_CODE`, `CALENDAR`.

**`TRIPS`** — the view-backed one. `CREATE TABLE TAXI_SRC.TRIPS LIKE NY_TAXI.BRONZE.CAB_TRIPS` captures the view's 24-column shape as a concrete table, then two audit columns are added:

- `LOAD_DATE DATE` — the logical day the row belongs to; the incremental key.
- `LAST_MODIFIED_TS TIMESTAMP_NTZ` — physical insert time, for freshness monitors later.

**`TAXI_OPS.LOAD_LOG`** — `RUN_DATE`, `RUN_TS`, `STATUS`, `TRIPS_LOADED`, `REFS_MERGED`, `NULL_DEFECTS`, `VARIANCE_DEFECTS`, `MESSAGE`. Append-only; this is how we later prove which day a given failure came from.

## 3. `TAXI_OPS.LOAD_DAILY_TAXI(P_RUN_DATE DATE)`

SQL proc, `EXECUTE AS OWNER`, inner `BEGIN ... EXCEPTION WHEN OTHER` so a failure still logs and emails. Colon-prefixed variable references throughout (`:P_RUN_DATE`, `:v_count`).

### Reference load — MERGE, never truncate

Each reference table is merged on its natural key from `NY_TAXI.BRONZE`:

```sql
MERGE INTO TAXI_SRC.VENDOR t
USING NY_TAXI.BRONZE.VENDOR s ON t.VENDOR_ID = s.VENDOR_ID
WHEN MATCHED THEN UPDATE SET t.VENDOR_NAME = s.VENDOR_NAME
WHEN NOT MATCHED THEN INSERT (VENDOR_ID, VENDOR_NAME) VALUES (s.VENDOR_ID, s.VENDOR_NAME);
```

Same shape for `DRIVERS` (`DRIVER_ID`), `LOCATION` (`LOCATION_ID`), `PAYMENT_TYPE`, `RATE_CODE`, `CALENDAR` (`CALENDAR_DATE`), `VENDOR_DETAILS` (`VENDOR_ID`, OBJECT column assigned as-is).

Note: `NY_TAXI.BRONZE.VENDOR` has 1,101 rows across 2 columns with no declared PK — if `VENDOR_ID` turns out to be non-unique in the source, `MERGE` will error rather than silently truncate. I check that during verification (step 6) and fall back to a `MERGE` against a `QUALIFY ROW_NUMBER()` deduplicated source if needed.

### Trip load — append-only, guarded

Deterministic per-day slice of the `CAB_TRIPS` view, re-stamped onto `:P_RUN_DATE`:

1. **Rerun guard** — the whole trip block is skipped if `EXISTS (SELECT 1 FROM TAXI_SRC.TRIPS WHERE LOAD_DATE = :P_RUN_DATE)`, so calling the proc twice for the same date is a no-op rather than a double-load. No delete, no truncate.
2. **Source day** — `MOD(DATEDIFF(day, '2026-09-02', :P_RUN_DATE), 7)` days after the view's minimum pickup date, so the sample rotates through the 7 available days and keeps its natural intra-day shape.
3. **Volume** — sampled to a tight `~12,000` rows (±2% jitter). Steady on purpose: source volume should be boring so that later, a downstream anomaly is unambiguously the transform's fault.
4. **Re-stamp** — `PICKUP_DATETIME` / `DROPOFF_DATETIME` shifted onto `:P_RUN_DATE` preserving time-of-day; `TRIP_ID` regenerated as a date-prefixed sequence so it stays unique across days; `LOAD_DATE = :P_RUN_DATE`; `LAST_MODIFIED_TS = CURRENT_TIMESTAMP()`.

### Planted defects

Both fire every day, both scoped to rows the proc itself inserts, so they are countable and attributable.

- **A — NULL join key.** 3-6 extra trips with `PU_LOCATION_ID = NULL`. Realistic (the actual TLC feed emits these) and cleanly caught by a `not_null` test later.
- **B — business-rule breach.** 4-8 trips where `TOTAL_AMOUNT` is off by a random $3-$18 from \`FARE\_AMOUNT + EXTRA + MTA\_TAX + TIP\_AMOUNT + TOLLS\_AMOUNT + IMPROVEMENT\_SURCHARGE
  - CONGESTION\_SURCHARGE + AIRPORT\_FEE + CBD\_CONGESTION\_FEE\`.

Every other column on the defect rows is left clean, and the main sample is left fully clean (valid vendor / payment / rate-code IDs, positive distance and fare, non-null timestamps, dropoff after pickup). That is what makes the future "large set of passing tests" genuinely pass rather than pass by accident.

### Logging and email

Insert one `LOAD_LOG` row, then `SYSTEM$SEND_EMAIL('NZSF_EMAIL_ALERTS', 'scott.walker@coalesce.io', 'Taxi Daily Load: <STATUS> (<date>)', <summary>)` with row counts and defect counts. The email call sits in its own exception block so a mail failure never fails the load.

## 4. `TAXI_OPS.TRIGGER_COALESCE_JOB(P_ENVIRONMENT_ID, P_JOB_ID)`

Same Python proc as `apac-demo`: `POST /scheduler/startRun`, poll `/scheduler/runStatus` every 15s up to 600s, return `SUCCESS` / `SUCCESS (with test failures)` / `FAILED` / `TIMEOUT`. Signature stays fully parameterised with **no default job ID** — jobs get rebuilt in the modelling phase.

Depends on a network rule + secret + external access integration. I will confirm the correct Coalesce app hostname with you before creating the network rule — `apac-demo` used `app.australia-southeast1.gcp.coalescesoftware.io`, which may not be right for this account — and check whether the existing `NZSF_TEST.COALESCE_API_TOKEN` secret is still valid or needs recreating under `TAXI_OPS`.

## 5. Tasks

- `TASK_LOAD_DAILY_TAXI` — `USING CRON 0 6 * * *` (timezone to confirm), warehouse `COMPUTE_WH`, calls `LOAD_DAILY_TAXI(CURRENT_DATE())`. Created **suspended**; resumed only after verification passes.
- `TASK_RUN_TAXI_PIPELINE` — `AFTER TASK_LOAD_DAILY_TAXI`, calls `TRIGGER_COALESCE_JOB`. Created **suspended** and left that way until a job ID exists.

## 6. Verification — the gate before any node work

Backfill by calling the proc manually for \~10 consecutive dates (a range that includes at least two Tuesdays and two Thursdays, since the eventual volume-monitor story is day-of-week based), then check:

1. **Schema fidelity** — diff `TAXI_SRC` column names / types / ordinal positions against `NY_TAXI.BRONZE` via `INFORMATION_SCHEMA.COLUMNS`. Must match exactly, including the two appended audit columns on `TRIPS`.
2. **Reference counts** — `TAXI_SRC` reference tables match `NY_TAXI.BRONZE` row for row (1,101 / 1,101 / 250 / 265 / 7 / 7 / 2,000), and re-running the proc does not change them.
3. **Trip volume per day** — `GROUP BY LOAD_DATE`: 10 days present, each within ±2% of \~12,000, no gaps, no day loaded twice.
4. **Rerun idempotency** — call the proc a second time for a date already loaded; trip count for that `LOAD_DATE` is unchanged, reference counts unchanged, nothing truncated.
5. **Uniqueness** — `TRIP_ID` unique across the whole table, not just within a day.
6. **Defect counts** — exact count of `PU_LOCATION_ID IS NULL` and exact count of rows where `ABS(TOTAL_AMOUNT - <component sum>) > 0.01`, per `LOAD_DATE`, matching what `LOAD_LOG` recorded.
7. **Cleanliness of the rest** — zero unexpected nulls in `VENDOR_ID`, `PAYMENT_TYPE_ID`, `RATE_CODE_ID`, `TOTAL_AMOUNT`, `PICKUP_DATETIME`, `DROPOFF_DATETIME`; all `PAYMENT_TYPE_ID` / `RATE_CODE_ID` values resolvable against their reference tables; zero `DROPOFF_DATETIME < PICKUP_DATETIME`; zero non-defect rows failing the fare-sum rule.
8. **Timestamp re-stamping** — every trip's `DATE(PICKUP_DATETIME)` equals its `LOAD_DATE`.
9. **Email** — a `Taxi Daily Load: SUCCESS` mail actually arrives.
10. **`VENDOR_ID` uniqueness in the source** — confirms whether the `VENDOR` / `VENDOR_DETAILS` merges are safe as written (see step 3 note).

I'll report these as a table of actual-vs-expected and stop there.

## Deferred to later plans

- **Modelling plan** — `SILVER` staging nodes (including the deliberately buggy row-dropping stage that will break a volume monitor), dimensions, `FCT_TRIP`, `GOLD` reporting, plus rebuilt jobs, any new subgraphs, and the `SILVER`/`GOLD` location mappings.
- **Quality plan** — `synq_monitors.yml` (passing tests, one `not_null` failure, one business-rule failure, volume and freshness monitors) and `synq_recon.yaml` (passing reconciliations plus one that fails end-to-end).

## Critical files

- ../apac-demo/snowflake\_objects.sql - proven template for the proc, email, Python trigger and task chain
- workspace.yml - `BRONZE` remapped to `SWALKER_DB_DEV.TAXI_SRC`
- environments/Production-18.yml - same remap for the Production environment
- nodes/, jobs/, subgraphs/ - all contents deleted

## Open items to confirm

- Coalesce app hostname for this account (drives the network rule).
- Whether `NZSF_TEST.COALESCE_API_TOKEN` is still valid or needs recreating.
- Cron timezone for `TASK_LOAD_DAILY_TAXI` (`COMPUTE_WH` assumed as the warehouse).
