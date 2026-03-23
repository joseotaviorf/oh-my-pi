WITH funnel_summary AS (
    SELECT
        sk_supply,
        sk_house,
        nm_business_context,
        MAX(funnel_order) AS max_stage,
        MAX(date) AS max_stage_date,
        MAX(CASE WHEN funnel_order = 5 THEN planning_conversion END) AS opportunity_conversion
    FROM
        dw_growth.obt_supply
    GROUP BY
        1, 2, 3
),
ranked AS (
    SELECT
        sk_supply,
        nm_business_context,
        ROW_NUMBER() OVER (
          PARTITION BY
            CASE
              WHEN sk_house > 0 THEN CAST(sk_house AS varchar(255))
              ELSE sk_supply
            END
          ORDER BY
            max_stage DESC,
            max_stage_date,
            CASE WHEN opportunity_conversion = 'FSS' THEN 0 ELSE 1 END,
            CASE WHEN nm_business_context = 'RENT' THEN 0 ELSE 1 END
        ) AS rnk
    FROM
        funnel_summary
)
SELECT
    sk_supply,
    nm_business_context,
    'Unique' as fl_unique
FROM
    ranked
WHERE
    rnk = 1