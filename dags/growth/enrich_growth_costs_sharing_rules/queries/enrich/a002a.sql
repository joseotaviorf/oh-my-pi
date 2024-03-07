WITH monthly_budget_share AS (
    SELECT DISTINCT
        adt.year_month,
        atr.city_group,
        (
            FLOAT(SUM(budget) OVER(PARTITION BY year_month, city_group))/
            NULLIF(FLOAT(SUM(budget) OVER(PARTITION BY year_month)), 0)
        ) AS share
    FROM
        datalake_gsheets_clean.marketing_affiliates_targets_replanning AS atr
    INNER JOIN
        datalake_quintoandar.aux_date AS adt
            ON DATE(NULLIF(atr.dt_target, '')) = adt.date
),
date_region_cross_join AS (
    SELECT DISTINCT
        adt.id_date,
        adt.year_month,
        rgn.city_group
    FROM
        datalake_quintoandar.aux_date AS adt, datalake_region.region AS rgn
)
SELECT
    drc.id_date,
    '{id_rule}' AS id_rule,
    drc.city_group,
    COALESCE(mbs.share,0) AS share,
    'affiliates' AS funnel_side,
    CAST(NULL AS STRING) AS business_context
FROM
    date_region_cross_join AS drc
INNER JOIN
    monthly_budget_share AS mbs
        ON drc.year_month=mbs.year_month
        AND drc.city_group=mbs.city_group