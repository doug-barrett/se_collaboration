@id("ab76adbf-738b-4460-9586-02a4d5e20d3e")
@nodeType("10")

SELECT
    VENDOR_ID                     @isBusinessKey,
    YEAR                          @isBusinessKey,
    MONTH                         @isBusinessKey,
    VENDOR_NAME,
    TRIP_COUNT,
    TOTAL_FARE_AMOUNT,
    TOTAL_AMOUNT,
    TOTAL_AMOUNT_CASH,
    TOTAL_AMOUNT_CC,
    TOTAL_AMOUNT_VOID
FROM {{ ref("SILVER", "STG_YELLOW_CAB_VENDOR_MONTHLY") }}
