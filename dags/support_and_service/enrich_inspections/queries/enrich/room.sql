WITH room_type AS (
    SELECT
        rt.id_room_type,
        rt.type AS room_type
    FROM
        datalake_inspections_clean.room_type rt
    QUALIFY
        rt.ts_updated= FIRST(rt.ts_updated) OVER(PARTITION BY rt.id_room_type ORDER BY rt.ts_updated DESC)
)
SELECT
    r.id_room,
    r.id_assessment,
    rt.id_room_type,
    r.room_name,
    rt.room_type,
    r.ts_created,
    r.ts_updated,
    r.year,
    r.month,
    r.day
FROM
    datalake_inspections_clean.room r
JOIN
    room_type rt
        ON r.id_type = rt.id_room_type
WHERE
    MAKE_DATE(r.year, r.month, r.day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')