@id("e8d0ce9f-896c-4484-b131-fc1f54540898")
@nodeType("6")
SELECT
  VENDOR_ID,
  VENDOR_NAME
FROM {{ ref("BRONZE", "VENDOR") }}
