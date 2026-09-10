@id("cb070501-18ae-4c4a-b933-a0491922f453")
@nodeType("8")

SELECT
    VENDOR_ID                     @isBusinessKey,
    VENDOR_NAME,
    LICENSE_ISSUED_DATE,
    1 AS SYSTEM_VERSION           @isSystemVersion,
    'Y' AS SYSTEM_CURRENT_FLAG    @isSystemCurrentFlag
FROM {{ ref("SILVER", "ODS_VENDOR") }}
WHERE SYSTEM_CURRENT_FLAG = 'Y'
