@id("bc1a1f29-4e14-4750-b7e7-21aeade877cd")
@nodeType("9")

SELECT
    LOCATION_ID                   @isBusinessKey,
    BOROUGH,
    ZONE,
    SERVICE_ZONE,
    FILENAME,
    ZONE_EFFECTIVE_DATE,
    UPDATED_AT,
    1 AS SYSTEM_VERSION           @isSystemVersion,
    'Y' AS SYSTEM_CURRENT_FLAG    @isSystemCurrentFlag
FROM {{ ref("SILVER", "STG_LOCATION") }}
