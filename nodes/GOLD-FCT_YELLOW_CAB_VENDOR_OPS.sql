@id("30917b0f-7eaa-4422-af4e-33074e30134b")
@nodeType("10")

SELECT
    VENDOR_ID                     @isBusinessKey,
    YEAR                          @isBusinessKey,
    MONTH                         @isBusinessKey,
    VENDOR_NAME,
    TRIP_COUNT,
    TRIP_DISTANCE_TOTAL,
    TRIP_DISTANCE_AVG,
    TRIP_DURATION_MINUTES_TOTAL
FROM {{ ref("SILVER", "STG_YELLOW_CAB_VENDOR_MONTHLY") }}
