SELECT
    id_date,
    id_city,
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
    MAX(CASE WHEN count_workdays = 9 THEN dt_workday ELSE NULL END) AS dt_end_8,
    MAX(CASE WHEN count_workdays = 10 THEN dt_workday ELSE NULL END) AS dt_end_9,
    MAX(CASE WHEN count_workdays = 11 THEN dt_workday ELSE NULL END) AS dt_end_10,
    MAX(CASE WHEN count_workdays = 12 THEN dt_workday ELSE NULL END) AS dt_end_11,
    MAX(CASE WHEN count_workdays = 13 THEN dt_workday ELSE NULL END) AS dt_end_12,
    MAX(CASE WHEN count_workdays = 14 THEN dt_workday ELSE NULL END) AS dt_end_13,
    MAX(CASE WHEN count_workdays = 15 THEN dt_workday ELSE NULL END) AS dt_end_14,
    MAX(CASE WHEN count_workdays = 16 THEN dt_workday ELSE NULL END) AS dt_end_15
FROM
    datalake_date.cities_calendar
WHERE
    count_workdays BETWEEN 1 AND 16
GROUP BY
    1, 2, 3, 4
