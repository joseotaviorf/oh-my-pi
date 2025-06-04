SELECT
    id,
    acquireMessage AS acquire_message,
    amount,
    cardId AS id_card,
    CAST(createdAt AS TIMESTAMP) AS ts_created,
    currency,
    customerId AS id_customer,
    CAST(dueAt AS TIMESTAMP) AS ts_due,
    gatewayId AS id_gateway,
    CAST(paidAt AS TIMESTAMP) AS ts_paid,
    paymentMethod AS payment_method,
    status,
    CAST(updatedAt AS TIMESTAMP) AS ts_updated,
    acquireReturnCode AS acquire_return_code,
    acquireAuthCode AS acquire_auth_code,
    acquireNsu AS acquire_nsu,
    acquireTid AS acquire_tid,
    acquireName AS acquire_name
FROM
    datalake_wall_street_raw.chargemundipagg
