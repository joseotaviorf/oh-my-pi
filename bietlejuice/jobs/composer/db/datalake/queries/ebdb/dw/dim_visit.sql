SELECT
    id AS sk_visit,
    id AS id_visit,
    code AS cd_visit,
    dt_visit,
    slot,
    slot_count,
    type,
    status,
    booking_type,
    ts_created,
    ts_updated,
    now() AS ts_load
FROM
    datalake_ebdb_clean.visit
