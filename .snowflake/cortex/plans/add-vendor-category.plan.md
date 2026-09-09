# Plan: Add Vendor Category to Pipeline

## Context

The **Vendor Category** definition from the catalog classifies vendors as:
- **ENTERPRISE** — vendors with more than 100 drivers
- **COMMERCIAL** — vendors with fewer than 100 drivers

The pipeline already has the pieces in place:
- `VENDOR_DETAILS` (BRONZE source) has the `DRIVERS` column (NUMBER(3,0))
- `SQL_VENDOR_DETAILS` (SQL Stage v2, SILVER) stages VENDOR_DETAILS and already contains a placeholder column: `'Category' as "Category"`
- `DIM_VENDOR_DETAILS` (Dimension, GOLD) sources from SQL_VENDOR_DETAILS

## Approach

The transformation belongs in the **stage** node (not the dimension), per project conventions. The placeholder column in `SQL_VENDOR_DETAILS` was clearly set up for this.

### Step 1 — Update `nodes/SILVER-SQL_VENDOR_DETAILS.sql`

Replace:
```sql
'Category' as "Category"
```
With:
```sql
CASE WHEN "DRIVERS" > 100 THEN 'ENTERPRISE' ELSE 'COMMERCIAL' END AS "VENDOR_CATEGORY"
```

This applies the exact catalog definition. The column is renamed from `Category` to `VENDOR_CATEGORY` to follow naming conventions.

### Step 2 — Rebuild SQL_VENDOR_DETAILS

```bash
coa create --include "{ SQL_VENDOR_DETAILS }"
coa run --include "{ SQL_VENDOR_DETAILS }"
```

### Step 3 — Rebuild DIM_VENDOR_DETAILS

```bash
coa create --include "{ DIM_VENDOR_DETAILS }"
coa run --include "{ DIM_VENDOR_DETAILS }"
```

The dimension will automatically pick up the new `VENDOR_CATEGORY` column from its upstream stage.

## What stays the same

- `DIM_VENDOR` (sourced from VENDOR, not VENDOR_DETAILS) is unaffected — it only carries VENDOR_ID and VENDOR_NAME.
- No new nodes are needed. The existing two-node path (stage → dimension) already exists.
