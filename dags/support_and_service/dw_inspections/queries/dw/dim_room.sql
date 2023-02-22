SELECT
    r.id_room AS sk_room,
    r.room_name,
    r.room_type,
    r.comment,
    r.ts_created,
    r.ts_updated,
    NOW() AS ts_load,
    r.year,
    r.month,
    r.day
FROM
    datalake_inspections.room r
WHERE
    r.year = {year}
    AND r.month = {month}
    AND r.day = {day}
