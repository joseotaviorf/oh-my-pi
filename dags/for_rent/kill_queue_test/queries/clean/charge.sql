SELECT
    id,
    reservation_id AS id_reservation,
    version, 
    CAST(created_at AS TIMESTAMP) AS ts_created,
    CAST(updated_at AS TIMESTAMP) AS ts_updated
FROM
    datalake_kill_queue_test_raw.charge