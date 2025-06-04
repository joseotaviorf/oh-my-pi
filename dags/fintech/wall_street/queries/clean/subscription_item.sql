SELECT
    id,
    subscriptionId AS id_subscription,
    code,
    businessEntityId AS id_business_entity,
    financeEntityId AS id_finance_entity,
    externalId AS id_external,
    status,
    priceInCents AS price_in_cents,
    cycles,
    quantity,
    CAST(canceledAt AS TIMESTAMP) AS ts_canceled,
    CAST(createdAt AS TIMESTAMP) AS ts_created,
    CAST(updatedAt AS TIMESTAMP) AS ts_updated
FROM
    datalake_wall_street_raw.subscriptionitem
