@id("8c9128f5-6d78-45a2-8f3e-8e4c7a5349ee")
@nodeType("6")
SELECT
  RATE_CODE_ID,
  RATE_CODE
FROM {{ ref("BRONZE", "RATE_CODE") }}
