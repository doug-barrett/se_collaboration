@id("b40b7958-43d6-46f3-a89e-813a4ee5c955")
@nodeType("6")
@testsEnabled
SELECT
  LOCATION_ID                   @isBusinessKey @tests("SELECT * FROM {{ this }} WHERE LOCATION_ID IS NULL", "SELECT LOCATION_ID, COUNT(*) FROM {{ this }} GROUP BY LOCATION_ID HAVING COUNT(*) > 1"),
  BOROUGH                       @tests("SELECT * FROM {{ this }} WHERE BOROUGH IS NULL"),
  ZONE                          @tests("SELECT * FROM {{ this }} WHERE ZONE IS NULL"),
  SERVICE_ZONE                  @tests("SELECT * FROM {{ this }} WHERE SERVICE_ZONE IS NULL"),
  FILENAME,
  ZONE_EFFECTIVE_DATE,
  UPDATED_AT
FROM {{ ref("BRONZE", "LOCATION") }}
QUALIFY ROW_NUMBER() OVER (PARTITION BY LOCATION_ID ORDER BY UPDATED_AT DESC) = 1
