SELECT
    id,
    feature_id              AS id_feature,
    consolidated_id         AS id_consolidated,
    business_entity_id      AS id_business_entity,
    finance_entity_id       AS id_finance_entity,
    external_payment_id     AS id_external_payment,
    source_client,
    status,
    city_state,
    city,
    description,
    year_month,
    event_date              AS dt_event,
    due_date                AS dt_due,
    created_at              AS ts_created,
    updated_at              AS ts_updated
FROM
    datalake_sap_gateway_homolog_raw.journal_entry
