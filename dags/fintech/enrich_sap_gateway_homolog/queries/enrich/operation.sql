SELECT
    id_operation,
    id_feature,
    id_business_partner,
    id_sync_sap_job,
    `description`,
    feature_op_ident,
    ts_reference,
    ts_due,
    ts_created,
    ts_updated,
    year,
    month,
    day
FROM
    datalake_sap_gateway_clean.operation
QUALIFY
    ROW_NUMBER() OVER (PARTITION BY id_operation ORDER BY ts_updated DESC) = 1
