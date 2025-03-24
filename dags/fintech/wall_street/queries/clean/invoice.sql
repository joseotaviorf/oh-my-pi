SELECT
    id,
    subscriptionId AS id_subscription,
    chargeId AS id_charge,
    externalId AS id_external,
    storeId AS id_store,
    priceInCents AS price_in_cents,
    status,
    externalCreatedAt AS ts_created_external,
    dueAt AS ts_due,
    billingAt AS ts_billing,
    paidAt AS ts_paid,
    canceledAt AS ts_canceled,
    createdAt AS ts_created,
    updatedAt AS ts_updated
FROM
    datalake_wall_street_raw.invoice
