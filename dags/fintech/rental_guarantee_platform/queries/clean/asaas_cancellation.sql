SELECT
    id,
    asaas_customer_id       AS id_asaas_customer,
    asaas_subscription_id   AS id_asaas_subscription, 
    batch_id                AS id_batch,
    propose                 AS id_propose, 
    status, 
    event,
    raw_request, 
    raw_response, 
    created_at              AS ts_created, 
    updated_at              AS ts_updated,
    canceled_at             AS ts_canceled,
    reversed_at             AS ts_reversed
FROM
    datalake_rental_guarantee_platform_raw.asaas_cancellation
