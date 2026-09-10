@id("498eaaab-3928-4fc8-bb6e-fc372d0e703e")
@nodeType("9")

SELECT
    VENDOR_ID                     @isBusinessKey,
    VENDOR_NAME,
    LICENSE_ISSUED_DATE,
    UPDATED_AT,
    1 AS SYSTEM_VERSION           @isSystemVersion,
    'Y' AS SYSTEM_CURRENT_FLAG    @isSystemCurrentFlag
FROM {{ ref("SILVER", "STG_VENDOR") }}
