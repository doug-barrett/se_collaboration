# NY Taxi DQ Demo — Synq Quality Plan

Four files: `.connections.yaml`, `synq_monitors.yml`, `synq_volume_monitors.yml`,
`synq_recon.yaml`.

## `.connections.yaml`

Pulled from apac-demo, databases changed to `[SWALKER_DB_DEV]`.

```yaml
connections:
  snowflake:
    snowflake:
      account: fka56740
      warehouse: COMPUTE_WH
      role: SYSADMIN
      auth_type: snowflake
      username: SWALKER2
      password: SnowCoaFlakeLesce2024
      databases: [SWALKER_DB_DEV]
  snowflake_target:
    snowflake:
      account: fka56740
      warehouse: COMPUTE_WH
      role: SYSADMIN
      auth_type: snowflake
      username: SWALKER2
      password: SnowCoaFlakeLesce2024
      databases: [SWALKER_DB_DEV]
```

## 1. `synq_monitors.yml` — tests + field stats + some monitors

Namespace: `taxi-data-quality`.

### All 47 tests (45 pass + 2 fail)

(Unchanged from previous plan — see full listing in the plan card.)

**Source TAXI_SRC.TRIPS** — 6 passing: not_null on TRIP_ID, VENDOR_ID, PICKUP_DATETIME,
DROPOFF_DATETIME, LOAD_DATE; unique on TRIP_ID.

**STG_YELLOW_CAB_TRIPS** — 8 passing + **1 FAILING** (`stg_trips_not_null_pu_location`):
not_null on TRIP_ID, VENDOR_ID, PICKUP_DATETIME, DROPOFF_DATETIME, PAYMENT_TYPE_ID,
RATE_CODE_ID; unique TRIP_ID; business_rule TRIP_DISTANCE >= 0. Fails on PU_LOCATION_ID
not_null (planted defect, 3-6 rows/day).

**STG_VENDOR** — 3: not_null VENDOR_ID, unique VENDOR_ID, not_null VENDOR_NAME.

**STG_LOCATION** — 5: not_null + unique LOCATION_ID, not_null BOROUGH/ZONE/SERVICE_ZONE.

**STG_PAYMENT_TYPE** — 3: not_null + unique PAYMENT_TYPE_ID, not_null PAYMENT_TYPE.

**STG_RATE_CODE** — 3: not_null + unique RATE_CODE_ID, not_null RATE_CODE.

**ODS_YELLOW_CAB_TRIPS** — 2: unique TRIP_ID (where current), accepted_values
SYSTEM_CURRENT_FLAG.

**BIZ_YELLOW_CAB_TRIPS** — 4: not_null TRIP_ID, not_null VENDOR_NAME, business_rule
dropoff > pickup, business_rule TOTAL_AMOUNT > 0.

**FCT_YELLOW_CAB_TRIPS** — 11 passing + **1 FAILING** (`fct_trips_fare_component_match`):
not_null on TRIP_ID/VENDOR_ID/PICKUP_DT/DROPOFF_DT/LOAD_DATE; unique TRIP_ID; business_rule
positive distance/fare; accepted_values PAYMENT_TYPE; referential integrity to DIM_VENDOR
and DIM_PAYMENT_TYPE. Fails on fare-component match (planted defect, 4-8 rows/day).

**FCT_VENDOR_FINANCIAL** — 4: not_null grain, positive trip_count, total >= fare, not_null
vendor_name.

**FCT_VENDOR_OPS** — 3: not_null grain, positive trip_count, positive distance_total.

**Field stats** on STG_YELLOW_CAB_TRIPS: PU_LOCATION_ID, PAYMENT_TYPE_ID, TOTAL_AMOUNT.

## 2. `synq_volume_monitors.yml` — 30 monitors (28 pass + 2 fail)

Namespace: `taxi-volume-freshness`.

### Source layer — TAXI_SRC (10 monitors, all pass)

| Entity | Monitors |
|---|---|
| `taxi_src.trips` | volume, freshness (LAST_MODIFIED_TS) |
| `taxi_src.vendor` | volume, freshness (UPDATED_AT) |
| `taxi_src.vendor_details` | volume, freshness (UPDATED_AT) |
| `taxi_src.location` | volume, freshness (UPDATED_AT) |
| `taxi_src.payment_type` | volume |
| `taxi_src.rate_code` | volume |

All green — the loader produces stable, predictable volumes. Source freshness monitors
prove the daily load is running. Vendor/location churn means freshness updates daily
even for reference tables.

### Staging layer — TAXI_SILVER stages (8 monitors, all pass)

| Entity | Monitors |
|---|---|
| `taxi_silver.stg_yellow_cab_trips` | volume, freshness (LAST_MODIFIED_TS) |
| `taxi_silver.stg_vendor` | volume, freshness (UPDATED_AT) |
| `taxi_silver.stg_location` | volume, freshness (UPDATED_AT) |
| `taxi_silver.stg_payment_type` | volume |
| `taxi_silver.stg_rate_code` | volume |

All green — stages truncate-and-reload from stable sources.

### ODS layer (5 monitors, all pass)

| Entity | Monitors |
|---|---|
| `taxi_silver.ods_yellow_cab_trips` | volume, freshness (LAST_MODIFIED_TS) |
| `taxi_silver.ods_vendor` | volume |
| `taxi_silver.ods_location` | volume |
| `taxi_silver.ods_payment_type` | volume |

All green — ODS accumulates, volumes only grow or stay stable.

### Business + Gold layer (7 monitors, 2 FAIL Tue/Thu)

| Entity | Monitors | Status |
|---|---|---|
| `taxi_silver.biz_yellow_cab_trips` | volume, freshness (LOAD_DATE) | **Volume FAILS Tue/Thu** |
| `taxi_gold.fct_yellow_cab_trips` | volume, freshness (LOAD_DATE) | **Volume FAILS Tue/Thu** |
| `taxi_gold.dim_vendor` | volume | Green |
| `taxi_gold.dim_location` | volume | Green |
| `taxi_gold.fct_yellow_cab_vendor_financial` | volume | Green |

Dim + vendor-fact monitors provide green anchors in the gold layer so the volume
drop is clearly isolated to the trip pipeline.

### Monitor layer story

When the Tue/Thu bug fires, the dashboard shows:
- Source (green) → STG (green) → ODS (green) → **BIZ (red)** → **FCT (red)**
- All reference chains (vendor, location, payment, rate code): green end to end

This immediately localises the problem: the volume loss starts at BIZ, not earlier.

## 3. `synq_recon.yaml` — 11 reconciliations (10 pass + 1 fail)

Name: `taxi-pipeline-recon`.

### Trip pipeline recons (4 pass + 1 fail)

| ID | Source → Target | Key | Status |
|---|---|---|---|
| `src-to-stg-trips` | `TAXI_SRC.TRIPS` → `TAXI_SILVER.STG_YELLOW_CAB_TRIPS` | TRIP_ID | Pass (1:1) |
| `stg-to-ods-trips` | `TAXI_SILVER.STG_YELLOW_CAB_TRIPS` → `TAXI_SILVER.ODS_YELLOW_CAB_TRIPS` (current) | TRIP_ID | Pass (1:1 after merge) |
| `biz-to-fct-trips` | `TAXI_SILVER.BIZ_YELLOW_CAB_TRIPS` → `TAXI_GOLD.FCT_YELLOW_CAB_TRIPS` | TRIP_ID | Pass (direct feed) |
| `ods-to-biz-trips` | `TAXI_SILVER.ODS_YELLOW_CAB_TRIPS` (current, TOTAL_AMOUNT > 0) → `TAXI_SILVER.BIZ_YELLOW_CAB_TRIPS` | TRIP_ID | Pass Mon/Wed/Fri/Sat/Sun, **FAIL Tue/Thu** |
| **`ods-to-fct-trips`** | `TAXI_SILVER.ODS_YELLOW_CAB_TRIPS` (current, TOTAL_AMOUNT > 0) → `TAXI_GOLD.FCT_YELLOW_CAB_TRIPS` | TRIP_ID | **FAIL Tue/Thu** (end-to-end) |

Wait — `ods-to-biz-trips` would also fail on Tue/Thu, giving us 2 failing recons not 1.
That's actually a stronger demo story (the pair localises the loss to BIZ), but the brief
said 1 failing recon. I'll include `ods-to-biz-trips` as the single failing recon and
**remove** `ods-to-fct-trips` — the localisation story is clearer with just one failure:
ODS → BIZ fails (the bug lives here), BIZ → FCT passes (downstream is clean).

Revised:

| ID | Source → Target | Key | Status |
|---|---|---|---|
| `src-to-stg-trips` | `TAXI_SRC.TRIPS` → `STG_YELLOW_CAB_TRIPS` | TRIP_ID | Pass |
| `stg-to-ods-trips` | `STG_YELLOW_CAB_TRIPS` → `ODS_YELLOW_CAB_TRIPS` (current) | TRIP_ID | Pass |
| `ods-to-biz-trips` | `ODS_YELLOW_CAB_TRIPS` (current, TOTAL_AMOUNT > 0) → `BIZ_YELLOW_CAB_TRIPS` | TRIP_ID | **FAIL Tue/Thu** |
| `biz-to-fct-trips` | `BIZ_YELLOW_CAB_TRIPS` → `FCT_YELLOW_CAB_TRIPS` | TRIP_ID | Pass |

### Reference pipeline recons (6 pass)

| ID | Source → Target | Key |
|---|---|---|
| `vendor-stg-to-ods` | `STG_VENDOR` → `ODS_VENDOR` | VENDOR_ID |
| `vendor-ods-to-dim` | `ODS_VENDOR` → `DIM_VENDOR` | VENDOR_ID |
| `location-stg-to-ods` | `STG_LOCATION` → `ODS_LOCATION` | LOCATION_ID |
| `location-ods-to-dim` | `ODS_LOCATION` → `DIM_LOCATION` | LOCATION_ID |
| `payment-stg-to-dim` | `STG_PAYMENT_TYPE` → `DIM_PAYMENT_TYPE` | PAYMENT_TYPE_ID |
| `ratecode-stg-to-dim` | `STG_RATE_CODE` → `DIM_RATE_CODE` | RATE_CODE_ID |

Payment and rate code skip the ODS→DIM split (only 7 rows each; a single
STG→DIM recon is sufficient). Vendor and location get the full two-hop chain
(STG→ODS + ODS→DIM) because they have enough rows and churn history to make
separate recons meaningful.

## Summary: pass/fail matrix

| Category | Total | Pass | Fail | Fail when? |
|---|---|---|---|---|
| Tests | 47 | 45 | 2 | Every day |
| Volume monitors | 20 | 18 | 2 | Tue/Thu |
| Freshness monitors | 9 | 9 | 0 | — |
| Field stats | 1 | 1 | 0 | — |
| Reconciliations | 10 | 9 | 1 | Tue/Thu |
| **Total** | **87** | **82** | **5** | |

## Critical files

- [../apac-demo/.connections.yaml](../apac-demo/.connections.yaml) — connection template
- [../apac-demo/synq_monitors.yml](../apac-demo/synq_monitors.yml) — YAML syntax reference
- [../apac-demo/synq_recon.yaml](../apac-demo/synq_recon.yaml) — recon syntax reference
- [nodes/SILVER-BIZ_YELLOW_CAB_TRIPS.sql](nodes/SILVER-BIZ_YELLOW_CAB_TRIPS.sql) — the volume bug
- [snowflake_objects.sql](snowflake_objects.sql) — planted defects in the loader
