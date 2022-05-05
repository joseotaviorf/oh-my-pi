/*Share de custos com base no budget do mensal*/

WITH
share AS (
    SELECT DISTINCT
        CAST(REPLACE(dd.year_month, '/', '') AS INTEGER) AS year_month,
        atr.city_group,
        (
            SUM(budget) OVER (PARTITION BY year_month, city_group)::FLOAT/
            NULLIF(SUM(budget) OVER (PARTITION BY year_month)::FLOAT, 0)
        ) AS share
    FROM
        datalake_raw.gsheets_marketing_affiliates_targets_replanning atr
        JOIN dim_date dd
            ON DATE(NULLIF(atr.date, ''))= dd.date
    ),
dim_distinct AS (
    SELECT DISTINCT
        dd.sk_date,
        CAST(REPLACE(dd.year_month, '/', '') AS INTEGER) AS year_month,
        dr.city_group
    FROM
        dim_date dd, dim_region dr
    )
SELECT
    d.sk_date AS id_date,
    d.city_group,
    COALESCE(s.share,0) AS share,
    'affiliates' AS funnel_side
FROM
    dim_distinct d
    JOIN share s
        ON d.year_month=s.year_month
        AND d.city_group=s.city_group