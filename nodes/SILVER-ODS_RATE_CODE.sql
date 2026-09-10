@id("20529d80-0333-4fde-a98b-225f294a5dd3")
@nodeType("9")

SELECT
    RATE_CODE_ID                  @isBusinessKey,
    RATE_CODE,
    TARIFF_EFFECTIVE_DATE,
    UPDATED_AT,
    1 AS SYSTEM_VERSION           @isSystemVersion,
    'Y' AS SYSTEM_CURRENT_FLAG    @isSystemCurrentFlag
FROM {{ ref("SILVER", "STG_RATE_CODE") }}
