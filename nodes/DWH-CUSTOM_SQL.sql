@id("aff36c26-28c4-4a20-8e97-66eb04c9166e")
@nodeType("176")
@preSQL("ALTER SESSION SET TIMEZONE = 'UTC'")
@postSQL("SELECT '1'")
@testsEnabled(true)
@pre_test("SELECT * FROM {{ ref('DWH', 'STG_RECENT_ORDER_SUMMARY') }} WHERE total_spend < 0
")

WITH max_date AS (
    SELECT MAX(O_ORDERDATE) AS max_order_date
    FROM {{ ref('DWH', 'STG_ORDERS') }}
),

recent_orders AS (
    SELECT
        O_ORDERKEY AS order_key,
        O_CUSTKEY AS customer_key,
        O_TOTALPRICE AS order_total,
        O_ORDERDATE AS order_date
    FROM {{ ref('DWH', 'STG_ORDERS') }} o
    CROSS JOIN max_date
    WHERE o.O_ORDERDATE >= DATEADD(MONTH, -3, max_date.max_order_date)
),

order_summary AS (
    SELECT
        order_date,
        COUNT(*) AS order_count,
        SUM(order_total) AS total_spend
    FROM recent_orders
    GROUP BY order_date
)

SELECT
    order_date,
    order_count,
    total_spend,
    total_spend / order_count AS avg_order_value
FROM order_summary
