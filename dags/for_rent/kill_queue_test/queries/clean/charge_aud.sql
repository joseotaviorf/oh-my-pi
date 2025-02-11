SELECT
    id,
    reservation_id AS id_reservation,
    rev,
    revtype AS rev_type,
    revend AS rev_end
FROM
    datalake_kill_queue_test_raw.charge_aud