WITH base_time AS (
    SELECT 
        WEEKDAY(CAST(date_column AS TIMESTAMP)) AS day_of_week,
        (UNIX_TIMESTAMP(date_column) - UNIX_TIMESTAMP(DATE_TRUNC('day', CAST(date_column AS TIMESTAMP)) + INTERVAL 8 HOUR))/900 AS slot_number,
        CAST(date_column AS TIMESTAMP) AS ts_slot
    FROM
        (VALUES(SEQUENCE(CAST('2019-01-01' AS TIMESTAMP),(CURRENT_DATE + INTERVAL 2 MONTH), (INTERVAL 15 MINUTE)))) AS t1(date_array)
        LATERAL VIEW EXPLODE(date_array) AS date_column
    WHERE
        HOUR(CAST(date_column AS TIMESTAMP)) BETWEEN 7 AND 21
        AND CAST(date_column AS TIMESTAMP) >= CAST('2019-01-01' AS TIMESTAMP)
)
SELECT 
    day_of_week,
    slot_number,
    ts_slot
FROM 
    base_time