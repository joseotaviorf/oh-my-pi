WITH room_type_ranked AS (
    SELECT
        rt.id_room_type,
        rt.type AS room_type,
        -- RANK, not ROW_NUMBER: the original ts_updated = FIRST(ts_updated) OVER (...)
        -- kept every row tied on the latest ts_updated.
        RANK() OVER (PARTITION BY rt.id_room_type ORDER BY rt.ts_updated DESC) AS rn
    FROM
        datalake_inspection_services_clean.room_type rt
),
room_type AS (
    SELECT
        id_room_type,
        room_type
    FROM
        room_type_ranked
    WHERE
        rn = 1
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
    datalake_inspection_services_clean.room r
JOIN
    room_type rt
        ON r.id_type = rt.id_room_type
WHERE
    MAKE_DATE(r.year, r.month, r.day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
