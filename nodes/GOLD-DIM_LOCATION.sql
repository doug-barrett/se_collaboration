@id("c635b235-2f37-4799-8499-52c128810e49")
@nodeType("8")

SELECT
    LOCATION_ID                   @isBusinessKey,
    BOROUGH,
    ZONE,
    SERVICE_ZONE,
    ZONE_EFFECTIVE_DATE,
    1 AS SYSTEM_VERSION           @isSystemVersion,
    'Y' AS SYSTEM_CURRENT_FLAG    @isSystemCurrentFlag
FROM {{ ref("SILVER", "ODS_LOCATION") }}
WHERE SYSTEM_CURRENT_FLAG = 'Y'
