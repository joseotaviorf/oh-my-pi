WITH distinct_days AS (
    SELECT
        MD5(id_user || '-' || journey) AS sk_journey,
        COUNT(DISTINCT dt_event) AS days_with_events
    FROM 
        datalake_sale_journey.sale_journey
    GROUP BY
        id_user, journey
),
calculate_dates AS (
    SELECT
        MD5(sj.id_user || '-' || sj.journey) AS sk_journey,
        sj.id_user || '-' || sj.journey AS bk_journey,
        COALESCE(BIGINT(sj.id_user), -1) AS sk_user,
        dd.days_with_events,
        MAX(sj.journey) OVER (PARTITION BY sj.id_user, sj.journey ORDER BY sj.ts_event) AS total_past_journey,
        MIN(sj.dt_event) OVER (PARTITION BY sj.id_user, sj.journey ORDER BY sj.ts_event) AS dt_journey_started,
        MAX(sj.dt_event) OVER (PARTITION BY sj.id_user, sj.journey ORDER BY sj.ts_event) AS dt_journey_ended,
        sj.ts_event
    FROM
        datalake_sale_journey.sale_journey AS sj
    LEFT JOIN
        distinct_days AS dd
            ON MD5(sj.id_user || '-' || sj.journey) = dd.sk_journey
    QUALIFY
        ROW_NUMBER() OVER (PARTITION BY id_user, journey ORDER BY ts_event DESC) = 1
)
SELECT
    sk_journey,
    bk_journey,
    sk_user,
    COALESCE(BIGINT(DATE_FORMAT(dt_journey_started, 'yyyyMMdd')), -1) AS sk_journey_started_date,
    COALESCE(BIGINT(DATE_FORMAT(dt_journey_ended, 'yyyyMMdd')), -1) AS sk_journey_ended_date,
    DATEDIFF(dt_journey_ended, dt_journey_started) AS days_of_journey,
    DATEDIFF(dt_journey_started, LAG(dt_journey_ended) OVER (PARTITION BY sk_user ORDER BY ts_event)) AS days_since_last_journey,
    days_with_events,
    total_past_journey,
    NOW() AS ts_load
FROM
    calculate_dates
