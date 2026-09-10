@id("3ca33098-6e83-453d-992b-28979684038e")
@nodeType("8")

SELECT
    PAYMENT_TYPE_ID               @isBusinessKey,
    PAYMENT_TYPE,
    1 AS SYSTEM_VERSION           @isSystemVersion,
    'Y' AS SYSTEM_CURRENT_FLAG    @isSystemCurrentFlag
FROM {{ ref("SILVER", "ODS_PAYMENT_TYPE") }}
WHERE SYSTEM_CURRENT_FLAG = 'Y'
