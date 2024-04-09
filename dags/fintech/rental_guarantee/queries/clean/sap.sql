SELECT
    id,
    business_entity_id AS id_business_entity,
    finance_entity_id AS id_finance_entity,
    feature_id AS id_feature,
    transaction_name,
    status AS sap_status,
    request,
    response,
    trigger,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
    datalake_rental_guarantee_raw.sap
