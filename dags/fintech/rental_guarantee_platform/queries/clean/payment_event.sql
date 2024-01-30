SELECT
    CAST(id AS BIGINT) AS id,
    CAST(payment AS BIGINT) AS id_payment,
    fine,
    interest,
    status,
    event,
    created_at AS ts_created,
    year,
    month,
    day
FROM
    datalake_rental_guarantee_platform_raw.payment_event
QUALIFY
    ROW_NUMBER() OVER (PARTITION BY id ORDER BY created_at DESC) = 1
