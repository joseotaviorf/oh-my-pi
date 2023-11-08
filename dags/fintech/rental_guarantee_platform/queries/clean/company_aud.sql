SELECT
    id,
    companyuuid AS uuid_company,
    businessunituuid AS uuid_business_unit,
    productuuid AS uuid_product,
    version,
    status,
    billing_model,
    rev,
    revend AS rev_end,
    revtype AS rev_type,
    agent_split_fee,
    billing_model_mod  AS mod_billing_model,
    companyuuid_mod AS mod_uuid_company,
    status_mod AS mod_status,
    businessunituuid_mod AS mod_uuid_businessunit,
    productuuid_mod AS mod_uuid_product,
    agent_split_fee_mod AS mod_split_fee,
    created_at AS ts_created
FROM
    datalake_rental_guarantee_platform_raw.company_aud
