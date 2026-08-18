WITH ranked_room AS (
    SELECT
        r.id_room AS sk_room,
        r.room_name,
        r.room_type,
        r.ts_created,
        r.ts_updated,
        r.year,
        r.month,
        r.day,
        ROW_NUMBER() OVER (PARTITION BY r.id_room ORDER BY r.ts_updated DESC) AS rn
    FROM
        datalake_inspections.room AS r
    WHERE
        MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
)
SELECT
    sk_room,
    room_name,
    room_type,
    ts_created,
    ts_updated,
    NOW() AS ts_load,
    year,
    month,
    day
FROM
    ranked_room
WHERE
    rn = 1
