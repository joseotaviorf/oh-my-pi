SELECT
    id,
    subscriptionId AS id_subscription,
    chargeId AS id_charge,
    externalId AS id_external,
    storeId AS id_store,
    priceInCents AS price_in_cents,
    status,
    CAST(externalCreatedAt AS TIMESTAMP) AS ts_created_external,
    CAST(dueAt AS TIMESTAMP) AS ts_due,
    CAST(billingAt AS TIMESTAMP) AS ts_billing,
    CAST(paidAt AS TIMESTAMP) AS ts_paid,
    CAST(canceledAt AS TIMESTAMP) AS ts_canceled,
    CAST(createdAt AS TIMESTAMP) AS ts_created,
    CAST(updatedAt AS TIMESTAMP) AS ts_updated
FROM
    datalake_wall_street_raw.invoice
