@id("fbe18e0a-ca94-4a0f-a8ea-cf5715880a2f")
@nodeType("6")
@testsEnabled
SELECT
  VENDOR_ID                     @isBusinessKey @tests("SELECT * FROM {{ this }} WHERE VENDOR_ID IS NULL", "SELECT VENDOR_ID, COUNT(*) FROM {{ this }} GROUP BY VENDOR_ID HAVING COUNT(*) > 1"),
  VENDOR_NAME                   @tests("SELECT * FROM {{ this }} WHERE VENDOR_NAME IS NULL"),
  LICENSE_ISSUED_DATE,
  UPDATED_AT
FROM {{ ref("BRONZE", "VENDOR") }}
QUALIFY ROW_NUMBER() OVER (PARTITION BY VENDOR_ID ORDER BY UPDATED_AT DESC) = 1
