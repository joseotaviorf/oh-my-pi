SELECT
    id,
    subscriptionId AS id_subscription,
    businessEntityId AS id_business_entity,
    financeEntityId AS id_finance_entity,
    externalId AS id_external,
    code,
    status,
    priceInCents AS price_in_cents,
    cycles,
    quantity,
    TIMESTAMP(canceledAt) AS ts_canceled,
    TIMESTAMP(createdAt) AS ts_created,
    TIMESTAMP(updatedAt) AS ts_updated
FROM
    datalake_wall_street_raw.subscriptionitem
