SELECT
    id AS id_queue,
    queue_sid AS id_queue_twilio,
    account_id AS id_account,
    type_id AS id_type,
    queue_friendly_name,
    attributes,
    order,
    TIMESTAMP(created_at) AS ts_created,
    TIMESTAMP(updated_at) AS ts_updated,
    year,
    month,
    day
FROM
    datalake_hefesto_raw.queue