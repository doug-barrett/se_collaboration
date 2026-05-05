@id("ea8dc3a9-8561-4d5c-8d6b-c37e9af3c863")
@nodeType("176")
SELECT
     "R_REGIONKEY" AS "R_REGIONKEY",
     "R_NAME" AS "R_NAME",
     "R_COMMENT" AS "R_COMMENT"
FROM {{ ref('SRC_SAMPLE', 'REGION') }} "REGION"