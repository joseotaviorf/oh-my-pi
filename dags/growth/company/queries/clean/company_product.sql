SELECT
    company_id AS id_company,
    product_id AS id_product,
    status,
    product_settings,
    deactivation_reason,
    deactivation_sub_reason,
    deactivation_additional_comment,
    ts_database_transaction
FROM
    datalake_company_raw.company_product