# Plan: Add Vendor Category and Fare Revenue Per Mile

## Current State

| Node | Status | Relevant Columns |
|---|---|---|
| `BRONZE-VENDOR_DETAILS` (source) | Exists locally | VENDOR_ID, HQ_ADDRESS_DETAILS, PHONE, DRIVERS |
| `SILVER-STG_VENDOR` | Exists | VENDOR_ID, VENDOR_NAME |
| `GOLD-DIM_VENDOR` | Exists — sources only from STG_VENDOR | VENDOR_ID (BK), VENDOR_NAME (change-tracking), SCD2 system cols |
| `SILVER-STG_YELLOW_CAB_VENDOR_MONTHLY` | Exists | Already has TRIP_DISTANCE_TOTAL = SUM(TRIP_DISTANCE) and TOTAL_FARE_AMOUNT = SUM(FARE_AMOUNT) |
| `GOLD-FCT_YELLOW_CAB_VENDOR_FINANCIAL` | Exists — missing distance and RPM | VENDOR_ID, YEAR, MONTH, TRIP_COUNT, TOTAL_FARE_AMOUNT, TOTAL_AMOUNT, payment splits |

**Workspace 17** already has `STG_VENDOR_DETAILS` and `DIM_VENDOR_DETAILS` as separate nodes, but the local node files don't include them. Rather than creating a separate dimension, this plan enriches `DIM_VENDOR` directly — cleaner for consumers (one vendor dimension, not two).

---

## Node Changes

### 1. New node: `SILVER-STG_VENDOR_DETAILS.yml`

- **Type:** Stage (V1 `.yml`)
- **Source:** `BRONZE-VENDOR_DETAILS`
- **Columns:**
  - `VENDOR_ID` — passthrough (NUMBER)
  - `PHONE` — passthrough (VARCHAR)
  - `DRIVER_COUNT` — renamed from DRIVERS (NUMBER)
  - `VENDOR_CATEGORY` — computed: `CASE WHEN "VENDOR_DETAILS"."DRIVERS" > 100 THEN 'ENTERPRISE' ELSE 'COMMERCIAL' END` (STRING)
- **Tests:** hasNull + isDistinct on VENDOR_ID, acceptedValues on VENDOR_CATEGORY (ENTERPRISE, COMMERCIAL)

### 2. Modified node: `GOLD-DIM_VENDOR.yml`

- **Change:** Add second source — LEFT JOIN to `STG_VENDOR_DETAILS` on VENDOR_ID
- **New columns (both change-tracking):**
  - `DRIVER_COUNT` (NUMBER) — from STG_VENDOR_DETAILS
  - `VENDOR_CATEGORY` (STRING) — from STG_VENDOR_DETAILS, acceptedValues test (ENTERPRISE, COMMERCIAL)
- **Join condition:**
  ```
  FROM {{ ref('SILVER', 'STG_VENDOR') }} "STG_VENDOR"
  LEFT JOIN {{ ref('SILVER', 'STG_VENDOR_DETAILS') }} "STG_VENDOR_DETAILS"
    ON "STG_VENDOR"."VENDOR_ID" = "STG_VENDOR_DETAILS"."VENDOR_ID"
  ```

### 3. Modified node: `GOLD-FCT_YELLOW_CAB_VENDOR_FINANCIAL.yml`

- **New columns (added before system cols):**
  - `TRIP_DISTANCE_TOTAL` (NUMBER) — passthrough from STG_YELLOW_CAB_VENDOR_MONTHLY (already aggregated there)
  - `FARE_REVENUE_PER_MILE` (NUMBER(12,4)) — transform: `ROUND("STG_YELLOW_CAB_VENDOR_MONTHLY"."TOTAL_FARE_AMOUNT" / NULLIF("STG_YELLOW_CAB_VENDOR_MONTHLY"."TRIP_DISTANCE_TOTAL", 0), 4)`
  - hasNull test on FARE_REVENUE_PER_MILE
- **Description update:** add "Includes Fare Revenue Per Mile yield metric."

---

## Build Order (coa CLI)

```
1. coa create --include "{ STG_VENDOR_DETAILS }"
   coa run    --include "{ STG_VENDOR_DETAILS }"

2. coa create --include "{ DIM_VENDOR }"
   coa run    --include "{ DIM_VENDOR }"

3. coa create --include "{ FCT_YELLOW_CAB_VENDOR_FINANCIAL }"
   coa run    --include "{ FCT_YELLOW_CAB_VENDOR_FINANCIAL }"
```

Steps 1-2 are for Vendor Category (stage then dim). Step 3 is independent (Fare Revenue Per Mile). DIM_VENDOR must be re-created because its DDL changes (new columns + new join).

---

## Design Decisions

- **Enrich DIM_VENDOR vs. separate DIM_VENDOR_DETAILS:** Chose to add VENDOR_CATEGORY and DRIVER_COUNT directly to DIM_VENDOR. The catalog definition treats Vendor Category as a vendor attribute, so consumers should find it on the vendor dimension without an extra join. The workspace has a separate DIM_VENDOR_DETAILS — if you prefer that pattern instead, let me know.
- **FARE_REVENUE_PER_MILE on the fact, not a view:** The catalog says this metric is typically computed at fleet/market/time-period level. Since FCT_YELLOW_CAB_VENDOR_FINANCIAL is already at vendor × month grain with pre-aggregated TOTAL_FARE_AMOUNT and TRIP_DISTANCE_TOTAL, the division is correct at this grain — no risk of the "average of ratios" problem the definition warns about.
- **NULLIF guard:** Protects against division-by-zero for months with zero trip distance (e.g., a vendor with no trips).
