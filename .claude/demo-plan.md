# NY Taxi demo pipeline — build plan

The exact spec for the SILVER + GOLD taxi analytics pipeline built on top of the existing BRONZE sources. This is the source of truth for `/demo-build` — build precisely this, in this order, regardless of how the live prompt is worded. Node types below match what's already validated in this workspace (a mix of Stage V2/Dimension/Fact and View) — build each node as the type listed, not whatever AGENTS.md's general preference says, since that preference predates this pipeline.

All Stage nodes use the real **SQL Stage v2** node type — `@nodeType("6")`, `.sql` file, `fileVersion: 2` (`nodeTypes/SQLStagev2-6/`, `name: SQL Stage v2`). Column types are inferred live from the warehouse at `coa create`/`coa run` time (CTAS pattern), so upstream dependencies must already exist in the warehouse for a node's types to resolve correctly — build layers in order. Node-level config (`preSQL`, `postSQL`, `tests`, non-default `insertStrategy`) is NOT settable via `.sql` annotations in this local `coa` CLI build (7.41.0-alpha.17) even when the node type declares a matching `attributeName` — annotations render for column-level flags (`@isBusinessKey`, `@description(...)`, etc.) but node-level ones (`@preSQL`, `@tests`) were empirically verified to be silently dropped. Any such config must be added via the `coa serve` UI after the node exists, and won't be tracked in the `.sql` file. Correction made 2026-08-25 — an earlier version of this plan incorrectly named node type `426` ("Copy of Stage", a workspace-local duplicate) as "Stage V2"; that was wrong and has been reverted.

Locations: BRONZE (`NY_TAXI.BRONZE`, already exists) → SILVER (`SWALKER_DB_DEV.SILVER`) → GOLD (`SWALKER_DB_DEV.GOLD`).

**Build mechanism:** `/demo-build` no longer authors these 16 files from scratch — it copies them from `.claude/demo-node-cache/`, which holds the exact validated content (confirmed working end-to-end via real `coa create`/`coa run` on 2026-08-25). `/demo-reset` only clears `nodes/`; it never touches the cache. If this spec changes, update the cached files to match — the cache, not regeneration, is what `/demo-build` pulls from.

## Layer 1 — reference stages (Stage V2, `@nodeType("6")`, `nodes/SILVER-*.sql`)

- **STG_VENDOR** ← `BRONZE.VENDOR`. Passthrough: `VENDOR_ID`, `VENDOR_NAME`.
- **STG_LOCATION** ← `BRONZE.LOCATION`. Passthrough: `LOCATION_ID`, `BOROUGH`, `ZONE`, `SERVICE_ZONE`, `FILENAME`.
- **STG_PAYMENT_TYPE** ← `BRONZE.PAYMENT_TYPE`. Passthrough: `PAYMENT_TYPE_ID`, `PAYMENT_TYPE`.
- **STG_RATE_CODE** ← `BRONZE.RATE_CODE`. Passthrough: `RATE_CODE_ID`, `RATE_CODE`.
- **STG_YELLOW_CAB_TRIPS** ← `BRONZE.YELLOW_CAB_TRIPS`.
  - Filter: `WHERE TO_DATE(PICKUP_DATETIME) BETWEEN CURRENT_DATE - 30 AND CURRENT_DATE` (rolling 30-day window).
  - Derived columns: `TRIP_DURATION_MINUTES = DATEDIFF(MINUTE, PICKUP_DATETIME, DROPOFF_DATETIME)`; `TRIP_AVG_SPEED = DIV0(TRIP_DISTANCE, TRIP_DURATION_MINUTES) * 60`; `PICKUP_TIME_OF_DAY = CASE WHEN DATEDIFF(HOUR, TO_DATE(PICKUP_DATETIME), PICKUP_DATETIME) < 12 THEN 'MORNING' ELSE 'AFTERNOON' END`.
  - All other fare/fee/passenger columns passthrough.

## Layer 2 — dimensions (Dimension, V1, table, `nodes/GOLD-*.yml`)

- **DIM_VENDOR** ← `SILVER.STG_VENDOR`. Business key `VENDOR_ID`, surrogate `DIM_VENDOR_KEY`. `VENDOR_NAME` flagged as change-tracking (SCD2). Direct 1:1, no joins/filters.
- **DIM_LOCATION** ← `SILVER.STG_LOCATION`. Business key `LOCATION_ID`, surrogate `DIM_LOCATION_KEY`. Standard SCD housekeeping only, no change-tracking columns.
- **DIM_PAYMENT_TYPE** ← `SILVER.STG_PAYMENT_TYPE`. Business key `PAYMENT_TYPE_ID`, surrogate `DIM_PAYMENT_TYPE_KEY`.
- **DIM_RATE_CODE** ← `SILVER.STG_RATE_CODE`. Business key `RATE_CODE_ID`, surrogate `DIM_RATE_CODE_KEY`.

## Layer 3 — location views (View, `nodes/SILVER-*.yml`, materialization view)

- **PICKUP_LOCATION** ← `GOLD.DIM_LOCATION`. Straight passthrough of all columns, renaming the surrogate key to `DIM_PICKUP_LOCATION_KEY`.
- **DROPOFF_LOCATION** ← `GOLD.DIM_LOCATION`. Same, renaming the surrogate key to `DIM_DROPOFF_LOCATION_KEY`.

## Layer 4 — enriched trips stage (Stage V2, `@nodeType("6")`, `nodes/SILVER-STG_YELLOW_CAB_TRIPS1.sql`)

One concern per stage — this is purely the dimension-key-attachment step, no other logic.

- ← `SILVER.STG_YELLOW_CAB_TRIPS` joined to `GOLD.DIM_VENDOR`, `GOLD.DIM_PAYMENT_TYPE`, `GOLD.DIM_RATE_CODE`, `SILVER.PICKUP_LOCATION`, `SILVER.DROPOFF_LOCATION`:
  - `LEFT JOIN DIM_VENDOR ON VENDOR_ID = DIM_VENDOR.VENDOR_ID`
  - `LEFT JOIN DIM_PAYMENT_TYPE ON PAYMENT_TYPE_ID = DIM_PAYMENT_TYPE.PAYMENT_TYPE_ID`
  - `LEFT JOIN DIM_RATE_CODE ON RATE_CODE_ID = DIM_RATE_CODE.RATE_CODE_ID`
  - `INNER JOIN PICKUP_LOCATION ON PU_LOCATION_ID = PICKUP_LOCATION.LOCATION_ID`
  - `INNER JOIN DROPOFF_LOCATION ON DO_LOCATION_ID = DROPOFF_LOCATION.LOCATION_ID`
- Adds: `VENDOR_NAME`, `PAYMENT_TYPE`, `RATE_CODE` descriptive attributes; surrogate keys `DIM_VENDOR_KEY`, `DIM_PAYMENT_TYPE_KEY`, `DIM_RATE_CODE_KEY`, `DIM_PICKUP_LOCATION_KEY`, `DIM_DROPOFF_LOCATION_KEY`; `PU_BOROUGH`/`DO_BOROUGH` from the location views.
- Node-level data-quality tests (continueOnFailure): improbable distance (>200mi on Cash/Credit Card), improbable tip (tip > fare, fare > 0, Cash/Credit Card), improbable duration (>180 min, Cash/Credit Card), zero distance with fare > 0. **Not present in the `.sql` file** — node-level `@tests` annotations don't render locally (see note above). Add these 4 tests via `coa serve`'s UI after the node is created; they exist in this plan's spec but not in version control.

## Layer 5 — trips fact (Fact, V1, table, `nodes/GOLD-FCT_YELLOW_CAB_TRIPS.yml`)

- ← `SILVER.STG_YELLOW_CAB_TRIPS1`. Grain: one row per trip. Keep clean — no transforms beyond what layer 4 already computed.
- Incremental replace logic:
  - `preSQL: DELETE FROM {{this}} WHERE TO_DATE(PICKUP_DATETIME) IN (SELECT DISTINCT TO_DATE(PICKUP_DATETIME) FROM STG_YELLOW_CAB_TRIPS1)`
  - Main SELECT filter: `WHERE TO_DATE(PICKUP_DATETIME) NOT IN (SELECT DISTINCT TO_DATE(PICKUP_DATETIME) FROM {{this}})`
- Columns: all trip attributes + the 5 dimension surrogate keys + `TRIP_DURATION_MINUTES`/`TRIP_AVG_SPEED` + `SYSTEM_CREATE_DATE`/`SYSTEM_UPDATE_DATE` housekeeping.

## Layer 6 — monthly vendor rollup stage (Stage V2, `@nodeType("6")`, `nodes/SILVER-STG_YELLOW_CAB_VENDOR_MONTHLY.sql`)

- ← `GOLD.FCT_YELLOW_CAB_TRIPS`. Grain: vendor + year + month (`GROUP BY 1, 2, 3`).
- Columns: `YEAR = YEAR(PICKUP_DATETIME)`, `MONTH = MONTH(PICKUP_DATETIME)`, `VENDOR_NAME = MAX(VENDOR_NAME)`, `TRIP_COUNT = COUNT(1)`, `TOTAL_FARE_AMOUNT = SUM(FARE_AMOUNT)`, `TOTAL_AMOUNT = SUM(TOTAL_AMOUNT)`, `TOTAL_AMOUNT_CASH = SUM(CASE WHEN PAYMENT_TYPE='Cash' THEN TOTAL_AMOUNT END)`, `TOTAL_AMOUNT_CC = SUM(CASE WHEN PAYMENT_TYPE='Credit card' THEN TOTAL_AMOUNT END)`, `TOTAL_AMOUNT_VOID = SUM(CASE WHEN PAYMENT_TYPE='Void' THEN TOTAL_AMOUNT END)`, `TRIP_DISTANCE_TOTAL = SUM(TRIP_DISTANCE)`, `TRIP_DISTANCE_AVG = AVG(TRIP_DISTANCE)`, `TRIP_DURATION_MINUTES_TOTAL = SUM(TRIP_DURATION_MINUTES)`.

## Layer 7 — vendor facts (Fact, V1, table, `nodes/GOLD-*.yml`)

Both are pure passthrough splits of the same monthly aggregate — no new logic, business key `VENDOR_ID` + `YEAR` + `MONTH` on both.

- **FCT_YELLOW_CAB_VENDOR_FINANCIAL** ← `SILVER.STG_YELLOW_CAB_VENDOR_MONTHLY`. Columns: `TRIP_COUNT`, `TOTAL_FARE_AMOUNT`, `TOTAL_AMOUNT`, `TOTAL_AMOUNT_CASH`, `TOTAL_AMOUNT_CC`, `TOTAL_AMOUNT_VOID`.
- **FCT_YELLOW_CAB_VENDOR_OPS** ← `SILVER.STG_YELLOW_CAB_VENDOR_MONTHLY`. Columns: `TRIP_COUNT`, `TRIP_DISTANCE_TOTAL`, `TRIP_DISTANCE_AVG`, `TRIP_DURATION_MINUTES_TOTAL`.

## Out of scope

`SYNQ_AUDIT-SYNQ_AUDIT.yml`, `SILVER-STG_SYNQ_AUDIT.yml`, `SILVER-V_SYNQ_AUDIT.yml` — an audit/test-framework branch wired to a specific test ID, unrelated to this pipeline. Never touched by `/demo-reset` or `/demo-build`.
