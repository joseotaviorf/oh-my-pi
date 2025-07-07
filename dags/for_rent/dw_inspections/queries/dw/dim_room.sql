SELECT
    r.id_room AS sk_room,
    r.room_name,
    r.room_type,
    r.ts_created,
    r.ts_updated,
    NOW() AS ts_load,
    r.year,
    r.month,
    r.day
FROM
    datalake_inspections.room r
WHERE
    MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
QUALIFY
    ROW_NUMBER() OVER (PARTITION BY id_room ORDER BY ts_updated DESC) = 1

