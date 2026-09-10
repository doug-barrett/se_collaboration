@id("eb4324e7-c407-433b-864a-3064851b2f99")
@nodeType("9")

SELECT
    PAYMENT_TYPE_ID               @isBusinessKey,
    PAYMENT_TYPE,
    UPDATED_AT,
    1 AS SYSTEM_VERSION           @isSystemVersion,
    'Y' AS SYSTEM_CURRENT_FLAG    @isSystemCurrentFlag
FROM {{ ref("SILVER", "STG_PAYMENT_TYPE") }}
