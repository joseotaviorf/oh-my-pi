SELECT
    id,
    propose_id AS id_propose,
    user_id AS id_user,
    external_id AS id_external,
    source_id AS id_source,
    next_attempt_id AS id_next_attempt,
    payment_request_id AS id_payment_request,
    payment_type,
    paid_value,
    status,
    raw_request,
    raw_response,
    event_date AS dt_event,
    payment_schedule_date AS dt_payment_scheduled,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_rental_guarantee_platform_raw.lannister_payment_register
QUALIFY
    ROW_NUMBER() OVER (PARTITION BY id ORDER BY updated_at DESC) = 1
