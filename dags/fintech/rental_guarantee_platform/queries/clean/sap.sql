SELECT
    id,
    business_entity_id AS id_business_entity,
    finance_entity_id AS id_finance_entity,
    feature_id AS id_feature,
    request,
    response,
    status,
    trigger,
    transaction_name,
    created_at AS ts_created
FROM
    datalake_rental_guarantee_platform_raw.sap
