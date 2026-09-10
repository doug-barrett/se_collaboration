-- ============================================================================
-- NY Taxi DQ Demo — Phase 1: Data Prep infrastructure
-- ============================================================================
-- Sources live in SWALKER_DB_DEV.TAXI_SRC (mapped to the Coalesce BRONZE location).
-- Procs / tasks / load log live in SWALKER_DB_DEV.TAXI_OPS.
--
-- GROUND RULE: nothing in this script ever truncates or deletes. Reference data
-- is MERGEd on its natural key; trips are appended behind a LOAD_DATE guard so a
-- rerun for an already-loaded date is a no-op. This keeps Coalesce incremental
-- templates and Synq monitor history intact.
--
-- Seed data is READ from NY_TAXI.PUBLIC.YELLOW_CAB_TRIPS_RAW (44M rows, 338 days).
-- We deliberately do NOT read NY_TAXI.BRONZE.CAB_TRIPS: that view is a rolling
-- CURRENT_DATE-7..CURRENT_DATE-1 window, so its contents drift daily and would
-- make the loader non-reproducible. A fixed seed week is used instead.
-- ============================================================================

USE SCHEMA SWALKER_DB_DEV.TAXI_OPS;

-- ----------------------------------------------------------------------------
-- 1. Schemas
-- ----------------------------------------------------------------------------
CREATE SCHEMA IF NOT EXISTS SWALKER_DB_DEV.TAXI_SRC;
CREATE SCHEMA IF NOT EXISTS SWALKER_DB_DEV.TAXI_OPS;

-- ----------------------------------------------------------------------------
-- 2. Source tables — CREATE TABLE LIKE preserves exact column names, types,
--    order and precision from the NY_TAXI.BRONZE originals.
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS SWALKER_DB_DEV.TAXI_SRC.VENDOR         LIKE NY_TAXI.BRONZE.VENDOR;
CREATE TABLE IF NOT EXISTS SWALKER_DB_DEV.TAXI_SRC.VENDOR_DETAILS LIKE NY_TAXI.BRONZE.VENDOR_DETAILS;
CREATE TABLE IF NOT EXISTS SWALKER_DB_DEV.TAXI_SRC.DRIVERS        LIKE NY_TAXI.BRONZE.DRIVERS;
CREATE TABLE IF NOT EXISTS SWALKER_DB_DEV.TAXI_SRC.LOCATION       LIKE NY_TAXI.BRONZE.LOCATION;
CREATE TABLE IF NOT EXISTS SWALKER_DB_DEV.TAXI_SRC.PAYMENT_TYPE   LIKE NY_TAXI.BRONZE.PAYMENT_TYPE;
CREATE TABLE IF NOT EXISTS SWALKER_DB_DEV.TAXI_SRC.RATE_CODE      LIKE NY_TAXI.BRONZE.RATE_CODE;
CREATE TABLE IF NOT EXISTS SWALKER_DB_DEV.TAXI_SRC.CALENDAR       LIKE NY_TAXI.BRONZE.CALENDAR;

-- TRIPS takes the CAB_TRIPS view's 24-column shape as a real table, plus two
-- audit columns: LOAD_DATE (the incremental key) and LAST_MODIFIED_TS (freshness).
CREATE TABLE IF NOT EXISTS SWALKER_DB_DEV.TAXI_SRC.TRIPS LIKE NY_TAXI.BRONZE.CAB_TRIPS;
ALTER TABLE SWALKER_DB_DEV.TAXI_SRC.TRIPS ADD COLUMN IF NOT EXISTS LOAD_DATE DATE;
ALTER TABLE SWALKER_DB_DEV.TAXI_SRC.TRIPS ADD COLUMN IF NOT EXISTS LAST_MODIFIED_TS TIMESTAMP_NTZ(9);

-- ----------------------------------------------------------------------------
-- 2b. Incremental / business date columns.
--     This is the ONE deliberate divergence of TAXI_SRC from NY_TAXI.BRONZE:
--     every reference table gets UPDATED_AT as its incremental key, plus a
--     realistic business date where one genuinely fits. TRIPS already has
--     LOAD_DATE (business) and LAST_MODIFIED_TS (audit), so it is untouched.
-- ----------------------------------------------------------------------------
ALTER TABLE SWALKER_DB_DEV.TAXI_SRC.VENDOR         ADD COLUMN IF NOT EXISTS LICENSE_ISSUED_DATE DATE;
ALTER TABLE SWALKER_DB_DEV.TAXI_SRC.VENDOR         ADD COLUMN IF NOT EXISTS UPDATED_AT TIMESTAMP_NTZ(9);
ALTER TABLE SWALKER_DB_DEV.TAXI_SRC.VENDOR_DETAILS ADD COLUMN IF NOT EXISTS UPDATED_AT TIMESTAMP_NTZ(9);
ALTER TABLE SWALKER_DB_DEV.TAXI_SRC.DRIVERS        ADD COLUMN IF NOT EXISTS UPDATED_AT TIMESTAMP_NTZ(9);
ALTER TABLE SWALKER_DB_DEV.TAXI_SRC.LOCATION       ADD COLUMN IF NOT EXISTS ZONE_EFFECTIVE_DATE DATE;
ALTER TABLE SWALKER_DB_DEV.TAXI_SRC.LOCATION       ADD COLUMN IF NOT EXISTS UPDATED_AT TIMESTAMP_NTZ(9);
ALTER TABLE SWALKER_DB_DEV.TAXI_SRC.PAYMENT_TYPE   ADD COLUMN IF NOT EXISTS UPDATED_AT TIMESTAMP_NTZ(9);
ALTER TABLE SWALKER_DB_DEV.TAXI_SRC.RATE_CODE      ADD COLUMN IF NOT EXISTS TARIFF_EFFECTIVE_DATE DATE;
ALTER TABLE SWALKER_DB_DEV.TAXI_SRC.RATE_CODE      ADD COLUMN IF NOT EXISTS UPDATED_AT TIMESTAMP_NTZ(9);
ALTER TABLE SWALKER_DB_DEV.TAXI_SRC.CALENDAR       ADD COLUMN IF NOT EXISTS UPDATED_AT TIMESTAMP_NTZ(9);

-- One-time backfill of the new columns for rows loaded before they existed.
-- Additive population of brand-new columns, not a corrective rewrite.
UPDATE SWALKER_DB_DEV.TAXI_SRC.VENDOR
SET LICENSE_ISSUED_DATE = DATEADD(day, -MOD(ABS(HASH(VENDOR_ID)), 3650), DATE '2026-01-01'),
    UPDATED_AT = '2026-08-27 06:00:00'::TIMESTAMP_NTZ
WHERE UPDATED_AT IS NULL OR LICENSE_ISSUED_DATE IS NULL;

UPDATE SWALKER_DB_DEV.TAXI_SRC.VENDOR_DETAILS SET UPDATED_AT = '2026-08-27 06:00:00'::TIMESTAMP_NTZ WHERE UPDATED_AT IS NULL;
UPDATE SWALKER_DB_DEV.TAXI_SRC.DRIVERS        SET UPDATED_AT = '2026-08-27 06:00:00'::TIMESTAMP_NTZ WHERE UPDATED_AT IS NULL;
UPDATE SWALKER_DB_DEV.TAXI_SRC.PAYMENT_TYPE   SET UPDATED_AT = '2026-08-27 06:00:00'::TIMESTAMP_NTZ WHERE UPDATED_AT IS NULL;
UPDATE SWALKER_DB_DEV.TAXI_SRC.CALENDAR       SET UPDATED_AT = '2026-08-27 06:00:00'::TIMESTAMP_NTZ WHERE UPDATED_AT IS NULL;

UPDATE SWALKER_DB_DEV.TAXI_SRC.LOCATION
SET ZONE_EFFECTIVE_DATE = DECODE(MOD(ABS(HASH(LOCATION_ID)), 4),
        0, DATE '2011-01-01', 1, DATE '2015-07-01', 2, DATE '2019-01-01', DATE '2023-06-01'),
    UPDATED_AT = '2026-08-27 06:00:00'::TIMESTAMP_NTZ
WHERE UPDATED_AT IS NULL OR ZONE_EFFECTIVE_DATE IS NULL;

UPDATE SWALKER_DB_DEV.TAXI_SRC.RATE_CODE
SET TARIFF_EFFECTIVE_DATE = DECODE(RATE_CODE_ID,
        1,  DATE '2022-12-19',   -- Standard rate
        2,  DATE '2019-02-01',   -- JFK flat fare
        3,  DATE '2018-01-01',   -- Newark
        4,  DATE '2018-01-01',   -- Nassau / Westchester
        5,  DATE '2025-01-05',   -- Negotiated fare
        6,  DATE '2022-12-19',   -- Group ride
        99, DATE '2018-01-01'),  -- Unknown rate code
    UPDATED_AT = '2026-08-27 06:00:00'::TIMESTAMP_NTZ
WHERE UPDATED_AT IS NULL OR TARIFF_EFFECTIVE_DATE IS NULL;

-- ----------------------------------------------------------------------------
-- 3. Load log — append-only run history, used to attribute defects to a date.
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS SWALKER_DB_DEV.TAXI_OPS.LOAD_LOG (
    RUN_DATE           DATE,
    RUN_TS             TIMESTAMP_NTZ(9),
    STATUS             VARCHAR(20),
    TRIPS_LOADED       NUMBER(38,0),
    REFS_MERGED        NUMBER(38,0),   -- new keys + churn versions inserted
    NULL_DEFECTS       NUMBER(38,0),
    VARIANCE_DEFECTS   NUMBER(38,0),
    MESSAGE            VARCHAR(16777216)
);

-- ============================================================================
-- 4. LOAD_DAILY_TAXI — the daily loader.
--
--    Reference tables : APPEND-ONLY, CDC style. New keys get a first version;
--                       ~2% of keys per day get an additional version row with
--                       a later UPDATED_AT. No MERGE, no UPDATE, no truncate.
--                       Latest-version-per-key is resolved in the stage layer.
--    Trips            : append-only, guarded on LOAD_DATE.
--    Planted defects  : A) 3-6 rows with NULL PU_LOCATION_ID
--                       B) 4-8 rows where TOTAL_AMOUNT != sum of its components
--    Everything else is deliberately clean so future passing tests pass on
--    merit rather than by luck.
-- ============================================================================
CREATE OR REPLACE PROCEDURE SWALKER_DB_DEV.TAXI_OPS.LOAD_DAILY_TAXI(
    P_RUN_DATE DATE DEFAULT CURRENT_DATE(),
    P_SEND_EMAIL BOOLEAN DEFAULT TRUE
)
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS OWNER
AS
DECLARE
    v_status            VARCHAR DEFAULT 'SUCCESS';
    v_error_msg         VARCHAR DEFAULT '';
    v_message           VARCHAR DEFAULT '';
    v_refs_new          INTEGER DEFAULT 0;
    v_refs_churned      INTEGER DEFAULT 0;
    v_trips_loaded      INTEGER DEFAULT 0;
    v_null_defects      INTEGER DEFAULT 0;
    v_variance_defects  INTEGER DEFAULT 0;
    v_already_loaded    INTEGER DEFAULT 0;
    v_seed_date         DATE;
    v_updated_at        TIMESTAMP_NTZ;
    v_target_rows       INTEGER DEFAULT 0;
    v_summary           VARCHAR;
BEGIN
    BEGIN
        -- ------------------------------------------------------------------
        -- Seed day: map the run date's ISO weekday onto a FIXED seed week
        -- (2026-01-12 Mon .. 2026-01-18 Sun, every day >87k raw rows). A
        -- Tuesday load therefore samples a Tuesday's traffic shape.
        -- ------------------------------------------------------------------
        v_seed_date := DATEADD(day, DAYOFWEEKISO(:P_RUN_DATE) - 1, DATE '2026-01-12');

        -- Deterministic target volume: 12,000 +/- 2%, stable per run date so a
        -- rerun or a rebuild produces the same number.
        v_target_rows := 12000 + (MOD(ABS(HASH(:P_RUN_DATE)), 481) - 240);

        -- Anchored to the run date, never CURRENT_TIMESTAMP(), so a rerun of the
        -- same logical day produces an identical high-water mark.
        v_updated_at := :P_RUN_DATE::TIMESTAMP_NTZ + INTERVAL '6 hours';

        -- ==================================================================
        -- Reference data: APPEND-ONLY, CDC style. No MERGE, no UPDATE.
        --   (a) new keys     -> insert a first version
        --   (b) churned keys -> insert a NEW version row with a later
        --                       UPDATED_AT (~2% of keys per day)
        --
        -- Churn selection is MOD(ABS(HASH(key, run_date)), 100) < 2, so it is
        -- deterministic: different rows churn on different days, but rerunning
        -- a given date selects the same rows.
        --
        -- The `latest.UPDATED_AT < :v_updated_at` guard does double duty: it
        -- makes a rerun a no-op (latest already equals v_updated_at), and it
        -- stops a backfill of an OLDER date from regressing a key.
        --
        -- Churn is a touch only - business columns keep matching BRONZE - with
        -- one exception: DRIVERS.RATING drifts, since driver ratings genuinely
        -- move and it gives the future dimension a slowly-changing attribute.
        -- ==================================================================

        -- ---- VENDOR ----
        INSERT INTO SWALKER_DB_DEV.TAXI_SRC.VENDOR
            (VENDOR_ID, VENDOR_NAME, LICENSE_ISSUED_DATE, UPDATED_AT)
        SELECT s.VENDOR_ID, s.VENDOR_NAME,
               DATEADD(day, -MOD(ABS(HASH(s.VENDOR_ID)), 3650), DATE '2026-01-01'),
               :v_updated_at
        FROM NY_TAXI.BRONZE.VENDOR s
        WHERE NOT EXISTS (SELECT 1 FROM SWALKER_DB_DEV.TAXI_SRC.VENDOR t
                          WHERE t.VENDOR_ID = s.VENDOR_ID);
        v_refs_new := :v_refs_new + SQLROWCOUNT;

        INSERT INTO SWALKER_DB_DEV.TAXI_SRC.VENDOR
            (VENDOR_ID, VENDOR_NAME, LICENSE_ISSUED_DATE, UPDATED_AT)
        WITH latest AS (
            SELECT t.* FROM SWALKER_DB_DEV.TAXI_SRC.VENDOR t
            QUALIFY ROW_NUMBER() OVER (PARTITION BY t.VENDOR_ID ORDER BY t.UPDATED_AT DESC) = 1
        )
        SELECT l.VENDOR_ID, l.VENDOR_NAME, l.LICENSE_ISSUED_DATE, :v_updated_at
        FROM latest l
        WHERE MOD(ABS(HASH(l.VENDOR_ID, :P_RUN_DATE)), 100) < 2
          AND l.UPDATED_AT < :v_updated_at;
        v_refs_churned := :v_refs_churned + SQLROWCOUNT;

        -- ---- VENDOR_DETAILS ----
        INSERT INTO SWALKER_DB_DEV.TAXI_SRC.VENDOR_DETAILS
            (VENDOR_ID, HQ_ADDRESS_DETAILS, PHONE, DRIVERS, UPDATED_AT)
        SELECT s.VENDOR_ID, s.HQ_ADDRESS_DETAILS, s.PHONE, s.DRIVERS, :v_updated_at
        FROM NY_TAXI.BRONZE.VENDOR_DETAILS s
        WHERE NOT EXISTS (SELECT 1 FROM SWALKER_DB_DEV.TAXI_SRC.VENDOR_DETAILS t
                          WHERE t.VENDOR_ID = s.VENDOR_ID);
        v_refs_new := :v_refs_new + SQLROWCOUNT;

        INSERT INTO SWALKER_DB_DEV.TAXI_SRC.VENDOR_DETAILS
            (VENDOR_ID, HQ_ADDRESS_DETAILS, PHONE, DRIVERS, UPDATED_AT)
        WITH latest AS (
            SELECT t.* FROM SWALKER_DB_DEV.TAXI_SRC.VENDOR_DETAILS t
            QUALIFY ROW_NUMBER() OVER (PARTITION BY t.VENDOR_ID ORDER BY t.UPDATED_AT DESC) = 1
        )
        SELECT l.VENDOR_ID, l.HQ_ADDRESS_DETAILS, l.PHONE, l.DRIVERS, :v_updated_at
        FROM latest l
        WHERE MOD(ABS(HASH(l.VENDOR_ID, :P_RUN_DATE)), 100) < 2
          AND l.UPDATED_AT < :v_updated_at;
        v_refs_churned := :v_refs_churned + SQLROWCOUNT;

        -- ---- DRIVERS (churn also drifts RATING by +/-0.1, clamped 1.0-5.0) ----
        INSERT INTO SWALKER_DB_DEV.TAXI_SRC.DRIVERS
            (DRIVER_ID, VENDOR_ID, FIRST_NAME, LAST_NAME, LICENSE_NUMBER, LICENSE_EXPIRY,
             PHONE, EMAIL, HIRE_DATE, RATING, IS_ACTIVE, UPDATED_AT)
        SELECT s.DRIVER_ID, s.VENDOR_ID, s.FIRST_NAME, s.LAST_NAME, s.LICENSE_NUMBER,
               s.LICENSE_EXPIRY, s.PHONE, s.EMAIL, s.HIRE_DATE, s.RATING, s.IS_ACTIVE,
               :v_updated_at
        FROM NY_TAXI.BRONZE.DRIVERS s
        WHERE NOT EXISTS (SELECT 1 FROM SWALKER_DB_DEV.TAXI_SRC.DRIVERS t
                          WHERE t.DRIVER_ID = s.DRIVER_ID);
        v_refs_new := :v_refs_new + SQLROWCOUNT;

        INSERT INTO SWALKER_DB_DEV.TAXI_SRC.DRIVERS
            (DRIVER_ID, VENDOR_ID, FIRST_NAME, LAST_NAME, LICENSE_NUMBER, LICENSE_EXPIRY,
             PHONE, EMAIL, HIRE_DATE, RATING, IS_ACTIVE, UPDATED_AT)
        WITH latest AS (
            SELECT t.* FROM SWALKER_DB_DEV.TAXI_SRC.DRIVERS t
            QUALIFY ROW_NUMBER() OVER (PARTITION BY t.DRIVER_ID ORDER BY t.UPDATED_AT DESC) = 1
        )
        SELECT l.DRIVER_ID, l.VENDOR_ID, l.FIRST_NAME, l.LAST_NAME, l.LICENSE_NUMBER,
               l.LICENSE_EXPIRY, l.PHONE, l.EMAIL, l.HIRE_DATE,
               LEAST(5.0, GREATEST(1.0,
                   l.RATING + DECODE(MOD(ABS(HASH(l.DRIVER_ID, :P_RUN_DATE)), 2), 0, 0.1, -0.1)
               ))::NUMBER(2,1),
               l.IS_ACTIVE, :v_updated_at
        FROM latest l
        WHERE MOD(ABS(HASH(l.DRIVER_ID, :P_RUN_DATE)), 100) < 2
          AND l.UPDATED_AT < :v_updated_at;
        v_refs_churned := :v_refs_churned + SQLROWCOUNT;

        -- ---- LOCATION ----
        INSERT INTO SWALKER_DB_DEV.TAXI_SRC.LOCATION
            (LOCATION_ID, BOROUGH, ZONE, SERVICE_ZONE, FILENAME, ZONE_EFFECTIVE_DATE, UPDATED_AT)
        SELECT s.LOCATION_ID, s.BOROUGH, s.ZONE, s.SERVICE_ZONE, s.FILENAME,
               DECODE(MOD(ABS(HASH(s.LOCATION_ID)), 4),
                      0, DATE '2011-01-01', 1, DATE '2015-07-01',
                      2, DATE '2019-01-01', DATE '2023-06-01'),
               :v_updated_at
        FROM NY_TAXI.BRONZE.LOCATION s
        WHERE NOT EXISTS (SELECT 1 FROM SWALKER_DB_DEV.TAXI_SRC.LOCATION t
                          WHERE t.LOCATION_ID = s.LOCATION_ID);
        v_refs_new := :v_refs_new + SQLROWCOUNT;

        INSERT INTO SWALKER_DB_DEV.TAXI_SRC.LOCATION
            (LOCATION_ID, BOROUGH, ZONE, SERVICE_ZONE, FILENAME, ZONE_EFFECTIVE_DATE, UPDATED_AT)
        WITH latest AS (
            SELECT t.* FROM SWALKER_DB_DEV.TAXI_SRC.LOCATION t
            QUALIFY ROW_NUMBER() OVER (PARTITION BY t.LOCATION_ID ORDER BY t.UPDATED_AT DESC) = 1
        )
        SELECT l.LOCATION_ID, l.BOROUGH, l.ZONE, l.SERVICE_ZONE, l.FILENAME,
               l.ZONE_EFFECTIVE_DATE, :v_updated_at
        FROM latest l
        WHERE MOD(ABS(HASH(l.LOCATION_ID, :P_RUN_DATE)), 100) < 2
          AND l.UPDATED_AT < :v_updated_at;
        v_refs_churned := :v_refs_churned + SQLROWCOUNT;

        -- ---- PAYMENT_TYPE (only 7 rows, so it churns only occasionally) ----
        INSERT INTO SWALKER_DB_DEV.TAXI_SRC.PAYMENT_TYPE
            (PAYMENT_TYPE_ID, PAYMENT_TYPE, UPDATED_AT)
        SELECT s.PAYMENT_TYPE_ID, s.PAYMENT_TYPE, :v_updated_at
        FROM NY_TAXI.BRONZE.PAYMENT_TYPE s
        WHERE NOT EXISTS (SELECT 1 FROM SWALKER_DB_DEV.TAXI_SRC.PAYMENT_TYPE t
                          WHERE t.PAYMENT_TYPE_ID = s.PAYMENT_TYPE_ID);
        v_refs_new := :v_refs_new + SQLROWCOUNT;

        INSERT INTO SWALKER_DB_DEV.TAXI_SRC.PAYMENT_TYPE
            (PAYMENT_TYPE_ID, PAYMENT_TYPE, UPDATED_AT)
        WITH latest AS (
            SELECT t.* FROM SWALKER_DB_DEV.TAXI_SRC.PAYMENT_TYPE t
            QUALIFY ROW_NUMBER() OVER (PARTITION BY t.PAYMENT_TYPE_ID ORDER BY t.UPDATED_AT DESC) = 1
        )
        SELECT l.PAYMENT_TYPE_ID, l.PAYMENT_TYPE, :v_updated_at
        FROM latest l
        WHERE MOD(ABS(HASH(l.PAYMENT_TYPE_ID, :P_RUN_DATE)), 100) < 2
          AND l.UPDATED_AT < :v_updated_at;
        v_refs_churned := :v_refs_churned + SQLROWCOUNT;

        -- ---- RATE_CODE ----
        INSERT INTO SWALKER_DB_DEV.TAXI_SRC.RATE_CODE
            (RATE_CODE_ID, RATE_CODE, TARIFF_EFFECTIVE_DATE, UPDATED_AT)
        SELECT s.RATE_CODE_ID, s.RATE_CODE,
               DECODE(s.RATE_CODE_ID,
                      1,  DATE '2022-12-19', 2,  DATE '2019-02-01',
                      3,  DATE '2018-01-01', 4,  DATE '2018-01-01',
                      5,  DATE '2025-01-05', 6,  DATE '2022-12-19',
                      99, DATE '2018-01-01'),
               :v_updated_at
        FROM NY_TAXI.BRONZE.RATE_CODE s
        WHERE NOT EXISTS (SELECT 1 FROM SWALKER_DB_DEV.TAXI_SRC.RATE_CODE t
                          WHERE t.RATE_CODE_ID = s.RATE_CODE_ID);
        v_refs_new := :v_refs_new + SQLROWCOUNT;

        INSERT INTO SWALKER_DB_DEV.TAXI_SRC.RATE_CODE
            (RATE_CODE_ID, RATE_CODE, TARIFF_EFFECTIVE_DATE, UPDATED_AT)
        WITH latest AS (
            SELECT t.* FROM SWALKER_DB_DEV.TAXI_SRC.RATE_CODE t
            QUALIFY ROW_NUMBER() OVER (PARTITION BY t.RATE_CODE_ID ORDER BY t.UPDATED_AT DESC) = 1
        )
        SELECT l.RATE_CODE_ID, l.RATE_CODE, l.TARIFF_EFFECTIVE_DATE, :v_updated_at
        FROM latest l
        WHERE MOD(ABS(HASH(l.RATE_CODE_ID, :P_RUN_DATE)), 100) < 2
          AND l.UPDATED_AT < :v_updated_at;
        v_refs_churned := :v_refs_churned + SQLROWCOUNT;

        -- ---- CALENDAR ----
        INSERT INTO SWALKER_DB_DEV.TAXI_SRC.CALENDAR
            (CALENDAR_DATE, YEAR, MONTH, MONTH_NAME, DAY_OF_MONTH, DAY_OF_WEEK,
             WEEK_OF_YEAR, DAY_OF_YEAR, QTR_OF_YEAR, UPDATED_AT)
        SELECT s.CALENDAR_DATE, s.YEAR, s.MONTH, s.MONTH_NAME, s.DAY_OF_MONTH,
               s.DAY_OF_WEEK, s.WEEK_OF_YEAR, s.DAY_OF_YEAR, s.QTR_OF_YEAR, :v_updated_at
        FROM NY_TAXI.BRONZE.CALENDAR s
        WHERE NOT EXISTS (SELECT 1 FROM SWALKER_DB_DEV.TAXI_SRC.CALENDAR t
                          WHERE t.CALENDAR_DATE = s.CALENDAR_DATE);
        v_refs_new := :v_refs_new + SQLROWCOUNT;

        INSERT INTO SWALKER_DB_DEV.TAXI_SRC.CALENDAR
            (CALENDAR_DATE, YEAR, MONTH, MONTH_NAME, DAY_OF_MONTH, DAY_OF_WEEK,
             WEEK_OF_YEAR, DAY_OF_YEAR, QTR_OF_YEAR, UPDATED_AT)
        WITH latest AS (
            SELECT t.* FROM SWALKER_DB_DEV.TAXI_SRC.CALENDAR t
            QUALIFY ROW_NUMBER() OVER (PARTITION BY t.CALENDAR_DATE ORDER BY t.UPDATED_AT DESC) = 1
        )
        SELECT l.CALENDAR_DATE, l.YEAR, l.MONTH, l.MONTH_NAME, l.DAY_OF_MONTH,
               l.DAY_OF_WEEK, l.WEEK_OF_YEAR, l.DAY_OF_YEAR, l.QTR_OF_YEAR, :v_updated_at
        FROM latest l
        WHERE MOD(ABS(HASH(l.CALENDAR_DATE, :P_RUN_DATE)), 100) < 2
          AND l.UPDATED_AT < :v_updated_at;
        v_refs_churned := :v_refs_churned + SQLROWCOUNT;

        -- ==================================================================
        -- Trips — append-only. Rerun guard: if this LOAD_DATE already has
        -- rows, skip entirely rather than delete or double-load.
        -- ==================================================================
        SELECT COUNT(*) INTO :v_already_loaded
        FROM SWALKER_DB_DEV.TAXI_SRC.TRIPS
        WHERE LOAD_DATE = :P_RUN_DATE;

        IF (:v_already_loaded > 0) THEN
            v_message := 'SKIPPED trips: LOAD_DATE ' || :P_RUN_DATE::VARCHAR
                      || ' already has ' || :v_already_loaded::VARCHAR
                      || ' rows (no truncate, no reload).';
        ELSE
            -- ----------------------------------------------------------------
            -- Clean base sample. Every predicate here exists so that the
            -- future "passing" tests genuinely pass: positive amounts,
            -- ordered timestamps, non-null keys, full referential integrity,
            -- and internally consistent fare arithmetic.
            -- ----------------------------------------------------------------
            INSERT INTO SWALKER_DB_DEV.TAXI_SRC.TRIPS
                (TRIP_ID, FILE_NAME, VENDOR_ID, PAYMENT_TYPE_ID, RATE_CODE_ID,
                 PICKUP_DATETIME, DROPOFF_DATETIME, DO_LOCATION_ID, PU_LOCATION_ID,
                 TRIP_DISTANCE, AIRPORT_FEE, CBD_CONGESTION_FEE, CONGESTION_SURCHARGE,
                 EXTRA, FARE_AMOUNT, IMPROVEMENT_SURCHARGE, MTA_TAX, PASSENGER_COUNT,
                 STORE_AND_FWD_FLAG, TIP_AMOUNT, TOLLS_AMOUNT, TOTAL_AMOUNT,
                 TPEP_PICKUP_DATETIME, TPEP_DROPOFF_DATETIME, LOAD_DATE, LAST_MODIFIED_TS)
            WITH clean AS (
                SELECT s.*
                FROM NY_TAXI.PUBLIC.YELLOW_CAB_TRIPS_RAW s
                WHERE TO_DATE(s.PICKUP_DATETIME) = :v_seed_date
                  AND s.TOTAL_AMOUNT   > 0
                  AND s.FARE_AMOUNT    > 0
                  AND s.TRIP_DISTANCE  > 0
                  AND s.PASSENGER_COUNT > 0
                  AND s.PICKUP_DATETIME  IS NOT NULL
                  AND s.DROPOFF_DATETIME IS NOT NULL
                  AND s.DROPOFF_DATETIME > s.PICKUP_DATETIME
                  AND s.VENDOR_ID       IS NOT NULL
                  AND s.PAYMENT_TYPE_ID IS NOT NULL
                  AND s.RATE_CODE_ID    IS NOT NULL
                  AND s.PU_LOCATION_ID  IS NOT NULL
                  AND s.DO_LOCATION_ID  IS NOT NULL
                  AND ABS(s.TOTAL_AMOUNT - (COALESCE(s.FARE_AMOUNT,0) + COALESCE(s.EXTRA,0)
                      + COALESCE(s.MTA_TAX,0) + COALESCE(s.TIP_AMOUNT,0)
                      + COALESCE(s.TOLLS_AMOUNT,0) + COALESCE(s.IMPROVEMENT_SURCHARGE,0)
                      + COALESCE(s.CONGESTION_SURCHARGE,0) + COALESCE(s.AIRPORT_FEE,0)
                      + COALESCE(s.CBD_CONGESTION_FEE,0))) <= 0.01
                  AND EXISTS (SELECT 1 FROM NY_TAXI.BRONZE.VENDOR v       WHERE v.VENDOR_ID = s.VENDOR_ID)
                  AND EXISTS (SELECT 1 FROM NY_TAXI.BRONZE.PAYMENT_TYPE p WHERE p.PAYMENT_TYPE_ID = s.PAYMENT_TYPE_ID)
                  AND EXISTS (SELECT 1 FROM NY_TAXI.BRONZE.RATE_CODE r    WHERE r.RATE_CODE_ID = s.RATE_CODE_ID)
                  AND EXISTS (SELECT 1 FROM NY_TAXI.BRONZE.LOCATION lp    WHERE lp.LOCATION_ID = s.PU_LOCATION_ID)
                  AND EXISTS (SELECT 1 FROM NY_TAXI.BRONZE.LOCATION ld    WHERE ld.LOCATION_ID = s.DO_LOCATION_ID)
            ),
            picked AS (
                SELECT c.*, ROW_NUMBER() OVER (ORDER BY HASH(c.TRIP_ID, :P_RUN_DATE)) AS RN
                FROM clean c
                QUALIFY RN <= :v_target_rows
            )
            SELECT
                TO_NUMBER(TO_CHAR(:P_RUN_DATE, 'YYYYMMDD')) * 1000000 + p.RN,
                'daily_load_' || TO_CHAR(:P_RUN_DATE, 'YYYYMMDD') || '.parquet',
                p.VENDOR_ID, p.PAYMENT_TYPE_ID, p.RATE_CODE_ID,
                -- Re-stamp onto the run date, preserving time-of-day and duration.
                DATEADD(second, TIMEDIFF(second, DATE_TRUNC('day', p.PICKUP_DATETIME), p.PICKUP_DATETIME),
                        :P_RUN_DATE::TIMESTAMP_TZ),
                DATEADD(second, TIMEDIFF(second, p.PICKUP_DATETIME, p.DROPOFF_DATETIME),
                        DATEADD(second, TIMEDIFF(second, DATE_TRUNC('day', p.PICKUP_DATETIME), p.PICKUP_DATETIME),
                        :P_RUN_DATE::TIMESTAMP_TZ)),
                p.DO_LOCATION_ID, p.PU_LOCATION_ID, p.TRIP_DISTANCE,
                p.AIRPORT_FEE, p.CBD_CONGESTION_FEE, p.CONGESTION_SURCHARGE, p.EXTRA,
                p.FARE_AMOUNT, p.IMPROVEMENT_SURCHARGE, p.MTA_TAX, p.PASSENGER_COUNT,
                p.STORE_AND_FWD_FLAG, p.TIP_AMOUNT, p.TOLLS_AMOUNT, p.TOTAL_AMOUNT,
                p.TPEP_PICKUP_DATETIME, p.TPEP_DROPOFF_DATETIME,
                :P_RUN_DATE, :v_updated_at
            FROM picked p;

            v_trips_loaded := SQLROWCOUNT;

            -- ----------------------------------------------------------------
            -- PLANTED DEFECT A — NULL join key.
            -- 3-6 trips with a NULL PU_LOCATION_ID. Realistic (the real TLC
            -- feed emits these) and cleanly caught by a not_null test.
            -- All other columns on these rows are left clean so they do not
            -- trip the other tests as collateral damage.
            -- ----------------------------------------------------------------
            v_null_defects := 3 + MOD(ABS(HASH(:P_RUN_DATE, 'NULLDEFECT')), 4);

            INSERT INTO SWALKER_DB_DEV.TAXI_SRC.TRIPS
                (TRIP_ID, FILE_NAME, VENDOR_ID, PAYMENT_TYPE_ID, RATE_CODE_ID,
                 PICKUP_DATETIME, DROPOFF_DATETIME, DO_LOCATION_ID, PU_LOCATION_ID,
                 TRIP_DISTANCE, AIRPORT_FEE, CBD_CONGESTION_FEE, CONGESTION_SURCHARGE,
                 EXTRA, FARE_AMOUNT, IMPROVEMENT_SURCHARGE, MTA_TAX, PASSENGER_COUNT,
                 STORE_AND_FWD_FLAG, TIP_AMOUNT, TOLLS_AMOUNT, TOTAL_AMOUNT,
                 TPEP_PICKUP_DATETIME, TPEP_DROPOFF_DATETIME, LOAD_DATE, LAST_MODIFIED_TS)
            SELECT
                TO_NUMBER(TO_CHAR(:P_RUN_DATE, 'YYYYMMDD')) * 1000000 + 900000 + t.RN,
                'daily_load_' || TO_CHAR(:P_RUN_DATE, 'YYYYMMDD') || '.parquet',
                t.VENDOR_ID, t.PAYMENT_TYPE_ID, t.RATE_CODE_ID,
                t.PICKUP_DATETIME, t.DROPOFF_DATETIME,
                t.DO_LOCATION_ID,
                NULL,                                   -- <<< the planted defect
                t.TRIP_DISTANCE, t.AIRPORT_FEE, t.CBD_CONGESTION_FEE,
                t.CONGESTION_SURCHARGE, t.EXTRA, t.FARE_AMOUNT,
                t.IMPROVEMENT_SURCHARGE, t.MTA_TAX, t.PASSENGER_COUNT,
                t.STORE_AND_FWD_FLAG, t.TIP_AMOUNT, t.TOLLS_AMOUNT, t.TOTAL_AMOUNT,
                t.TPEP_PICKUP_DATETIME, t.TPEP_DROPOFF_DATETIME,
                :P_RUN_DATE, :v_updated_at
            FROM (
                SELECT x.*, ROW_NUMBER() OVER (ORDER BY x.TRIP_ID) AS RN
                FROM SWALKER_DB_DEV.TAXI_SRC.TRIPS x
                WHERE x.LOAD_DATE = :P_RUN_DATE
                QUALIFY RN <= :v_null_defects
            ) t;

            v_null_defects := SQLROWCOUNT;

            -- ----------------------------------------------------------------
            -- PLANTED DEFECT B — business-rule breach.
            -- 4-8 trips where TOTAL_AMOUNT is off by $3-$18 from the sum of
            -- its components. Arithmetically consistent everywhere else, so a
            -- custom SQL test with a 1-cent tolerance flags exactly these.
            -- ----------------------------------------------------------------
            v_variance_defects := 4 + MOD(ABS(HASH(:P_RUN_DATE, 'VARDEFECT')), 5);

            INSERT INTO SWALKER_DB_DEV.TAXI_SRC.TRIPS
                (TRIP_ID, FILE_NAME, VENDOR_ID, PAYMENT_TYPE_ID, RATE_CODE_ID,
                 PICKUP_DATETIME, DROPOFF_DATETIME, DO_LOCATION_ID, PU_LOCATION_ID,
                 TRIP_DISTANCE, AIRPORT_FEE, CBD_CONGESTION_FEE, CONGESTION_SURCHARGE,
                 EXTRA, FARE_AMOUNT, IMPROVEMENT_SURCHARGE, MTA_TAX, PASSENGER_COUNT,
                 STORE_AND_FWD_FLAG, TIP_AMOUNT, TOLLS_AMOUNT, TOTAL_AMOUNT,
                 TPEP_PICKUP_DATETIME, TPEP_DROPOFF_DATETIME, LOAD_DATE, LAST_MODIFIED_TS)
            SELECT
                TO_NUMBER(TO_CHAR(:P_RUN_DATE, 'YYYYMMDD')) * 1000000 + 950000 + t.RN,
                'daily_load_' || TO_CHAR(:P_RUN_DATE, 'YYYYMMDD') || '.parquet',
                t.VENDOR_ID, t.PAYMENT_TYPE_ID, t.RATE_CODE_ID,
                t.PICKUP_DATETIME, t.DROPOFF_DATETIME,
                t.DO_LOCATION_ID, t.PU_LOCATION_ID,
                t.TRIP_DISTANCE, t.AIRPORT_FEE, t.CBD_CONGESTION_FEE,
                t.CONGESTION_SURCHARGE, t.EXTRA, t.FARE_AMOUNT,
                t.IMPROVEMENT_SURCHARGE, t.MTA_TAX, t.PASSENGER_COUNT,
                t.STORE_AND_FWD_FLAG, t.TIP_AMOUNT, t.TOLLS_AMOUNT,
                -- <<< the planted defect: total no longer equals its components
                ROUND(t.TOTAL_AMOUNT + 3 + MOD(ABS(HASH(t.TRIP_ID)), 16), 2),
                t.TPEP_PICKUP_DATETIME, t.TPEP_DROPOFF_DATETIME,
                :P_RUN_DATE, :v_updated_at
            FROM (
                SELECT x.*, ROW_NUMBER() OVER (ORDER BY x.TRIP_ID DESC) AS RN
                FROM SWALKER_DB_DEV.TAXI_SRC.TRIPS x
                WHERE x.LOAD_DATE = :P_RUN_DATE
                  AND x.PU_LOCATION_ID IS NOT NULL
                QUALIFY RN <= :v_variance_defects
            ) t;

            v_variance_defects := SQLROWCOUNT;
            v_trips_loaded := :v_trips_loaded + :v_null_defects + :v_variance_defects;

            v_message := 'Loaded trips for ' || :P_RUN_DATE::VARCHAR
                      || ' from seed day ' || :v_seed_date::VARCHAR || '.';
        END IF;

    EXCEPTION
        WHEN OTHER THEN
            v_status    := 'FAILED';
            v_error_msg := SQLERRM;
            v_message   := 'Load failed: ' || :v_error_msg;
    END;

    -- ------------------------------------------------------------------
    -- Log the run (append-only).
    -- ------------------------------------------------------------------
    INSERT INTO SWALKER_DB_DEV.TAXI_OPS.LOAD_LOG
        (RUN_DATE, RUN_TS, STATUS, TRIPS_LOADED, REFS_MERGED,
         NULL_DEFECTS, VARIANCE_DEFECTS, MESSAGE)
    VALUES
        (:P_RUN_DATE, CURRENT_TIMESTAMP()::TIMESTAMP_NTZ, :v_status, :v_trips_loaded,
         :v_refs_new + :v_refs_churned, :v_null_defects, :v_variance_defects, :v_message);

    v_summary := 'Taxi Daily Load - ' || :v_status || CHR(10)
        || 'Run date: '            || :P_RUN_DATE::VARCHAR         || CHR(10)
        || 'Seed day: '            || COALESCE(:v_seed_date::VARCHAR, 'n/a') || CHR(10)
        || 'Trips loaded: '        || :v_trips_loaded::VARCHAR     || CHR(10)
        || 'Reference new keys: '     || :v_refs_new::VARCHAR      || CHR(10)
        || 'Reference churn versions: '|| :v_refs_churned::VARCHAR  || CHR(10)
        || 'NULL PU_LOCATION_ID defects: ' || :v_null_defects::VARCHAR     || CHR(10)
        || 'Fare-variance defects: '       || :v_variance_defects::VARCHAR || CHR(10)
        || :v_message;

    -- Email is best-effort: a mail failure must never fail the load.
    -- P_SEND_EMAIL => FALSE keeps multi-day backfills quiet.
    IF (:P_SEND_EMAIL) THEN
        BEGIN
            CALL SYSTEM$SEND_EMAIL(
                'NZSF_EMAIL_ALERTS',
                'scott.walker@coalesce.io',
                'Taxi Daily Load: ' || :v_status || ' (' || :P_RUN_DATE::VARCHAR || ')',
                :v_summary
            );
        EXCEPTION
            WHEN OTHER THEN
                v_summary := :v_summary || CHR(10) || '(Email skipped: ' || SQLERRM || ')';
        END;
    END IF;

    RETURN :v_summary;
END;

-- ============================================================================
-- 5. TRIGGER_COALESCE_JOB — starts a Coalesce job and polls to completion.
--    Deliberately left UNWIRED: no default job ID. The environment and job IDs
--    get supplied once the pipeline jobs are rebuilt in the modelling phase.
--
--    Reuses the existing APAC objects rather than creating duplicates:
--      - NETWORK RULE  SWALKER_DB_DEV.NZSF_TEST.COALESCE_API_NETWORK_RULE
--                      -> app.australia-southeast1.gcp.coalescesoftware.io
--      - SECRET        SWALKER_DB_DEV.NZSF_TEST.COALESCE_API_TOKEN
--      - EXTERNAL ACCESS INTEGRATION COALESCE_API_ACCESS
--    The APAC host is correct for this project: the `default` coa profile points
--    there and pins environmentID=18, matching environments/Production-18.yml.
-- ============================================================================
CREATE OR REPLACE PROCEDURE SWALKER_DB_DEV.TAXI_OPS.TRIGGER_COALESCE_JOB(
    P_ENVIRONMENT_ID VARCHAR,
    P_JOB_ID VARCHAR
)
RETURNS VARCHAR
LANGUAGE PYTHON
RUNTIME_VERSION = '3.12'
PACKAGES = ('snowflake-snowpark-python', 'requests')
HANDLER = 'trigger_job'
EXTERNAL_ACCESS_INTEGRATIONS = (COALESCE_API_ACCESS)
SECRETS = ('coalesce_token' = SWALKER_DB_DEV.NZSF_TEST.COALESCE_API_TOKEN)
EXECUTE AS OWNER
AS
$$
import _snowflake
import requests
import time

BASE_URL = 'https://app.australia-southeast1.gcp.coalescesoftware.io'


def trigger_job(session, p_environment_id, p_job_id):
    if not p_environment_id or not p_job_id:
        return 'SKIPPED: environment ID and job ID must both be supplied.'

    token = _snowflake.get_generic_secret_string('coalesce_token')
    headers = {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'Authorization': f'Bearer {token}',
    }
    payload = {
        'runDetails': {
            'environmentID': p_environment_id,
            'jobID': p_job_id,
            'parallelism': 16,
        },
        'userCredentials': {'snowflakeAuthType': 'OAuth'},
    }

    resp = requests.post(f'{BASE_URL}/scheduler/startRun', headers=headers, json=payload)
    if resp.status_code != 200:
        return f'FAILED to start run: {resp.status_code} - {resp.text}'

    run_counter = resp.json().get('runCounter')
    if not run_counter:
        return f'FAILED: no runCounter in response: {resp.text}'

    max_wait, poll_interval, elapsed = 600, 15, 0
    run_status = 'unknown'

    while elapsed < max_wait:
        time.sleep(poll_interval)
        elapsed += poll_interval

        status_resp = requests.get(
            f'{BASE_URL}/scheduler/runStatus',
            headers=headers,
            params={'runCounter': run_counter},
        )
        if status_resp.status_code != 200:
            return f'FAILED to check status: {status_resp.status_code} - {status_resp.text}'

        status_data = status_resp.json()
        run_status = status_data.get('runStatus', 'unknown')

        if run_status == 'completed':
            result = f'SUCCESS: run {run_counter} completed'
            if status_data.get('hasTestFailures', False):
                result += ' (with test failures)'
            return result
        if run_status in ('failed', 'canceled'):
            return f'FAILED: run {run_counter} status: {run_status}'

    return f'TIMEOUT: run {run_counter} still {run_status} after {max_wait}s'
$$;

-- ============================================================================
-- 6. Tasks — daily chain. Both created SUSPENDED.
--    TASK_LOAD_DAILY_TAXI is resumed only after the sample data is verified.
--    TASK_RUN_TAXI_PIPELINE stays suspended until a Coalesce job ID exists.
-- ============================================================================
CREATE OR REPLACE TASK SWALKER_DB_DEV.TAXI_OPS.TASK_LOAD_DAILY_TAXI
    WAREHOUSE = COMPUTE_WH
    SCHEDULE  = 'USING CRON 0 6 * * * Pacific/Auckland'
    COMMENT   = 'Loads a day of taxi source data with planted DQ defects'
AS
    CALL SWALKER_DB_DEV.TAXI_OPS.LOAD_DAILY_TAXI(CURRENT_DATE());

CREATE OR REPLACE TASK SWALKER_DB_DEV.TAXI_OPS.TASK_RUN_TAXI_PIPELINE
    WAREHOUSE = COMPUTE_WH
    COMMENT   = 'Kicks off the Coalesce pipeline. Job ID not yet wired.'
    AFTER SWALKER_DB_DEV.TAXI_OPS.TASK_LOAD_DAILY_TAXI
AS
    CALL SWALKER_DB_DEV.TAXI_OPS.TRIGGER_COALESCE_JOB('', '');

-- Resume the loader only once the sample data has been verified.
-- TASK_RUN_TAXI_PIPELINE stays suspended until a Coalesce job ID is wired in.
ALTER TASK SWALKER_DB_DEV.TAXI_OPS.TASK_LOAD_DAILY_TAXI RESUME;

-- ============================================================================
-- 7. Backfill helper — email suppressed so a multi-day backfill stays quiet.
-- ============================================================================
-- DECLARE
--     v_d   DATE DEFAULT '2026-08-27'::DATE;
--     v_end DATE DEFAULT '2026-09-09'::DATE;
-- BEGIN
--     WHILE (:v_d <= :v_end) DO
--         CALL SWALKER_DB_DEV.TAXI_OPS.LOAD_DAILY_TAXI(:v_d, FALSE);
--         v_d := DATEADD(day, 1, :v_d);
--     END WHILE;
--     RETURN 'Backfill complete through ' || :v_end::VARCHAR;
-- END;
