SELECT
    id,
    rev,
    revtype as rev_type,
    revend as rev_end,
    reservation_id as id_reservation
FROM
    datalake_kill_queue_raw.charge_aud