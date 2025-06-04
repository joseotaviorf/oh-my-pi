SELECT
    id,
    acquire,
    code,
    businessEntityId AS id_business_entity,
    financeEntityId AS id_finance_entity,
    externalId AS id_external,
    customerId AS id_customer,
    storeId AS id_store,
    riskEntities AS risk_entities,
    currency,
    payerName AS payer_name,
    payerDocumentNumber AS payer_document_number,
    recurrence,
    creditCardId AS id_credit_card,
    status,
    CAST(startAt AS DATE) AS dt_start,
    CAST(canceledAt AS TIMESTAMP) AS ts_canceled,
    CAST(createdAt AS TIMESTAMP) AS ts_created,
    CAST(updatedAt AS TIMESTAMP) AS ts_updated
FROM
    datalake_wall_street_raw.subscription
