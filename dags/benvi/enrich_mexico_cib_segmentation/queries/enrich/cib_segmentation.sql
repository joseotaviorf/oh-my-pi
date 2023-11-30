WITH dim_cib AS (
    SELECT
        GET_JSON_OBJECT(a.details, '$.userExternalId') AS id_user,
        DATE(GET_JSON_OBJECT(a.details, '$.registeredAt')) AS dt_registered
    FROM
        datalake_big_agent.agent AS a
    INNER JOIN
        datalake_ebdb_user.user AS u
            ON u.id = GET_JSON_OBJECT(a.details, '$.userExternalId')
    WHERE
        u.country_code = 'MX'
),
base_months_since_registration AS (
    SELECT DISTINCT
        dc.id_user,
        ROUND(MONTHS_BETWEEN(ad.month_end, dc.dt_registered), 1) AS months_registered,
        ADD_MONTHS(ad.month_start, 1) AS dt_month_started_segmentation,
        GREATEST(ad.month_start, dc.dt_registered) AS dt_started,
        ad.month_end AS dt_ended,
        ad.year,
        ad.month
    FROM
        datalake_quintoandar.aux_date AS ad
    INNER JOIN
        dim_cib AS dc
            ON ad.month_start >= DATE_TRUNC('month' , dt_registered)
            AND ad.month_start <= MAKE_DATE({year}, {month}, '01')
    WHERE
        dc.id_user IS NOT NULL
        AND ad.month_start >= GREATEST(ADD_MONTHS(MAKE_DATE({year}, {month}, '01'), -1), DATE_TRUNC('month', dt_registered))
),
events_by_month AS (
    SELECT
        bmsr.id_user,
        SUM(IF(ce.event_type = 'FL', 1, 0)) AS first_listings,
        SUM(IF(ce.event_type = 'CS', 1, 0)) AS contracts_signed,
        bmsr.year,
        bmsr.month
    FROM
        base_months_since_registration AS bmsr
    LEFT JOIN
        datalake_mexico_cib_events.cib_events AS ce
            ON ce.year = bmsr.year
            AND ce.month = bmsr.month
            AND ce.id_cib = bmsr.id_user
    GROUP BY
        1, 4, 5
),
segmentation_rule_calculation AS (
    SELECT
        bmsr.id_user AS id_cib,
        'AVG' AS type_calculation,
        CASE
            WHEN bmsr.months_registered < 2 THEN AVG(COALESCE(ebm.first_listings, 0)) OVER (PARTITION BY bmsr.id_user ORDER BY bmsr.dt_started ASC ROWS BETWEEN 0 PRECEDING AND CURRENT ROW)
            ELSE AVG(COALESCE(ebm.first_listings, 0)) OVER (PARTITION BY bmsr.id_user ORDER BY bmsr.dt_started ASC ROWS BETWEEN 1 PRECEDING AND CURRENT ROW)
        END AS avg_fl,
        CASE
            WHEN bmsr.months_registered < 2 THEN AVG(COALESCE(ebm.contracts_signed, 0)) OVER (PARTITION BY bmsr.id_user ORDER BY bmsr.dt_started ASC ROWS BETWEEN 0 PRECEDING AND CURRENT ROW)
            ELSE AVG(COALESCE(ebm.contracts_signed, 0)) OVER (PARTITION BY bmsr.id_user ORDER BY bmsr.dt_started ASC ROWS BETWEEN 1 PRECEDING AND CURRENT ROW)
        END AS avg_cs,
        bmsr.months_registered,
        bmsr.dt_month_started_segmentation,
        bmsr.dt_started,
        bmsr.dt_ended,
        bmsr.year,
        bmsr.month
    FROM
        base_months_since_registration AS bmsr
    INNER JOIN
        events_by_month AS ebm
            ON ebm.year = bmsr.year
            AND ebm.month = bmsr.month
            AND ebm.id_user = bmsr.id_user
)
SELECT
    id_cib,
    type_calculation,
    CASE
        WHEN avg_fl >= 5 AND avg_cs >= 1 THEN 'Elite'
        WHEN avg_fl > 1 THEN 'Plus'
        ELSE 'Inter'
    END AS segmentation,
    avg_fl AS first_listings,
    avg_cs AS contracts_signed,
    months_registered,
    IF(months_registered < 2, 1, 2) AS months_calculation,
    dt_month_started_segmentation,
    dt_started,
    dt_ended,
    year,
    month
FROM
    segmentation_rule_calculation
WHERE
    year = {year}
    AND month = {month}
