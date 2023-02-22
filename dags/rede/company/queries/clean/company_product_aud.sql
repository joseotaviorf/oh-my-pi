SELECT
    company_id AS id_company,
    product_id AS id_product,
    product_settings,
    version,
    rev,
    revend AS rev_end,
    revtype AS rev_type,
    company_id_mod AS mod_id_company,
    product_id_mod AS mod_id_product,
    product_settings_mod AS mod_product_settings,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
    datalake_company_raw.company_product_aud
