WITH dim_cib AS (
    SELECT
        CAST(GET_JSON_OBJECT(a.details, '$.userExternalId') AS INTEGER) AS id_user,
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
        dc.dt_registered,
        ROUND(MONTHS_BETWEEN(ad.month_end, dc.dt_registered), 1) AS months_registered,
        ADD_MONTHS(ad.month_start, 1) AS dt_month_started_segmentation,
        GREATEST(ad.month_start, dc.dt_registered) AS dt_started,
        ad.month_end AS dt_ended
    FROM
        datalake_quintoandar.aux_date AS ad
    INNER JOIN
        dim_cib AS dc
            ON ad.month_start >= DATE_TRUNC('month' , dt_registered)
            AND ad.month_start <= MAKE_DATE({year}, {month}, 01)
    WHERE
        dc.id_user IS NOT NULL
        AND ad.month_start >= GREATEST(ADD_MONTHS(MAKE_DATE({year}, {month}, 01), -1), DATE_TRUNC('month', dt_registered))
),
events_by_month AS (
    SELECT
        bmsr.id_user,
        SUM(IF(ce.event_type = 'FL', 1, 0)) AS first_listings,
        SUM(IF(ce.event_type = 'CS', 1, 0)) AS contracts_signed,
        bmsr.dt_started
    FROM
        base_months_since_registration AS bmsr
    LEFT JOIN
        datalake_mexico_cib_events.cib_events AS ce
            ON ce.id_cib = bmsr.id_user
            AND DATE_TRUNC('month', ce.dt_event) = bmsr.dt_started
    GROUP BY
        1, 4
),
segmentation_rule_calculation AS (
    SELECT
        bmsr.id_user AS id_cib,
        'AVG' AS type_calculation,
        IF(
            bmsr.months_registered <= 2,
            AVG(COALESCE(ebm.first_listings, 0)) OVER (PARTITION BY bmsr.id_user ORDER BY bmsr.dt_started ASC ROWS BETWEEN 0 PRECEDING AND CURRENT ROW),
            AVG(COALESCE(ebm.first_listings, 0)) OVER (PARTITION BY bmsr.id_user ORDER BY bmsr.dt_started ASC ROWS BETWEEN 1 PRECEDING AND CURRENT ROW)
        ) AS avg_fl,
        IF(
            bmsr.months_registered <= 2,
            AVG(COALESCE(ebm.contracts_signed, 0)) OVER (PARTITION BY bmsr.id_user ORDER BY bmsr.dt_started ASC ROWS BETWEEN 0 PRECEDING AND CURRENT ROW),
            AVG(COALESCE(ebm.contracts_signed, 0)) OVER (PARTITION BY bmsr.id_user ORDER BY bmsr.dt_started ASC ROWS BETWEEN 1 PRECEDING AND CURRENT ROW)
        ) AS avg_cs,
        bmsr.months_registered,
        IF(months_registered <= 2, 1, 2) AS months_calculation,
        bmsr.dt_month_started_segmentation,
        IF(months_registered <= 2, bmsr.dt_started, GREATEST(ADD_MONTHS(bmsr.dt_started, -1), bmsr.dt_registered)) AS dt_started,
        bmsr.dt_ended,
        YEAR(dt_month_started_segmentation) AS year,
        MONTH(dt_month_started_segmentation) AS month
    FROM
        base_months_since_registration AS bmsr
    INNER JOIN
        events_by_month AS ebm
            ON ebm.id_user = bmsr.id_user
            AND ebm.dt_started = bmsr.dt_started
)
SELECT
    id_cib,
    CASE
        WHEN months_registered <= 2 THEN 1
        ELSE
          CASE
            WHEN avg_fl >= 5 AND avg_cs >= 1 THEN 2
            WHEN avg_fl > 1 THEN 1
            ELSE 0
          END
    END AS id_segmentation,
    type_calculation,
    CASE
        WHEN months_registered <= 2 THEN 'Plus'
        ELSE
          CASE
            WHEN avg_fl >= 5 AND avg_cs >= 1 THEN 'Elite'
            WHEN avg_fl > 1 THEN 'Plus'
            ELSE 'Inter'
          END
    END AS segmentation,
    avg_fl AS first_listings,
    avg_cs AS contracts_signed,
    months_registered,
    months_calculation,
    dt_month_started_segmentation,
    dt_started,
    dt_ended,
    year,
    month
FROM
    segmentation_rule_calculation
WHERE
    dt_month_started_segmentation = MAKE_DATE({year},{month},{day}) + INTERVAL 1 DAY
