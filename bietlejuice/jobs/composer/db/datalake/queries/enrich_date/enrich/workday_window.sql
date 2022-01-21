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
            ON r.id_city = sch.id_city 
            AND ad.date = sch.dt_holiday
    WHERE 
        r.level = 'Cidade'
),
workday_calendar AS (
    SELECT 
        cc.id_date,
        cc.id_city,
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
)
SELECT 
    CAST(id_date AS BIGINT) AS id_date,
    CAST(id_city AS BIGINT) AS id_city,
    city,
    dt_reference AS dt_ref,
    MAX(CASE WHEN count_workdays = 1 THEN dt_workday ELSE NULL END) AS dt_start,
    MAX(CASE WHEN count_workdays = 2 THEN dt_workday ELSE NULL END) AS dt_end_1,
    MAX(CASE WHEN count_workdays = 3 THEN dt_workday ELSE NULL END) AS dt_end_2,
    MAX(CASE WHEN count_workdays = 4 THEN dt_workday ELSE NULL END) AS dt_end_3,
    MAX(CASE WHEN count_workdays = 5 THEN dt_workday ELSE NULL END) AS dt_end_4,
    MAX(CASE WHEN count_workdays = 6 THEN dt_workday ELSE NULL END) AS dt_end_5,
    MAX(CASE WHEN count_workdays = 7 THEN dt_workday ELSE NULL END) AS dt_end_6,
    MAX(CASE WHEN count_workdays = 8 THEN dt_workday ELSE NULL END) AS dt_end_7,
    MAX(CASE WHEN count_workdays = 16 THEN dt_workday ELSE NULL END) AS dt_end_15
FROM 
    workday_calendar
WHERE 
    count_workdays IN (1, 2, 3, 4, 5, 6, 7, 8, 16)
GROUP BY 
    1, 2, 3, 4