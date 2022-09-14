WITH cities_calendar AS (
    SELECT
        r.id AS id_city,
        r.name AS city,
        ad.id_date,
        CASE
            WHEN ad.weekend = 'Weekend' OR ad.is_brz_holiday = 'Holiday' OR sch.dt_holiday IS NOT NULL THEN FALSE
            ELSE TRUE
        END is_workday,
        date AS dt_reference
    FROM
        datalake_region.region r
    CROSS JOIN
        datalake_quintoandar.aux_date ad
    LEFT JOIN
        datalake_gsheets_clean.service_city_holidays sch
            ON ad.date = sch.dt_holiday
            AND (r.id = sch.id_city OR sch.category = 'Nacional')
    WHERE
        r.level = 'Cidade'
)
SELECT
    CAST(cc.id_date AS BIGINT) AS id_date,
    CAST(cc.id_city AS BIGINT) AS id_city,
    cc.city,
    COUNT(w.is_workday) OVER(PARTITION BY w.id_city, cc.dt_reference ORDER BY w.id_city, w.dt_reference ROWS UNBOUNDED PRECEDING) AS count_workdays,
    cc.is_workday,
    DATE(cc.dt_reference) AS dt_reference,
    DATE(w.dt_reference) AS dt_workday
FROM
    cities_calendar cc
LEFT JOIN
    cities_calendar w
        ON cc.id_city = w.id_city
        AND w.dt_reference BETWEEN cc.dt_reference AND cc.dt_reference + interval '25' DAY
WHERE
    w.is_workday = TRUE
