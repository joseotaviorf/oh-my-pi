SELECT
    id,
    created_at AS ts_created,
    updated_at AS ts_updated,
    version,
    reservation_id as id_reservation
FROM
    datalake_kill_queue_raw.charge