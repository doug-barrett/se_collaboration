@id("70d35516-34ed-4991-b013-4d69f644eb18")
@nodeType("8")

SELECT
    RATE_CODE_ID                  @isBusinessKey,
    RATE_CODE,
    TARIFF_EFFECTIVE_DATE,
    1 AS SYSTEM_VERSION           @isSystemVersion,
    'Y' AS SYSTEM_CURRENT_FLAG    @isSystemCurrentFlag
FROM {{ ref("SILVER", "ODS_RATE_CODE") }}
WHERE SYSTEM_CURRENT_FLAG = 'Y'
