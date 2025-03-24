SELECT
    id,
    invoiceId AS id_invoice,
    subscriptionItemId AS id_subscription_item,
    createdAt AS ts_created,
    updatedAt AS ts_updated
FROM
    datalake_wall_street_raw.invoicesubscriptionitem
