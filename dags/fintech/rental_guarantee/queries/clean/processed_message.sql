SELECT
    subscriber_id AS id_subscriber,
    message_id AS id_message,
    created_at AS ts_created
FROM
    datalake_rental_guarantee_raw.processed_message
