SELECT
    id,
    prospect_id AS id_prospect,
    company_name,
    company_tax_id,
    real_estate_license_number,
    crm_used,
    number_of_properties,
    year,
    month,
    day
FROM
    datalake_rede_platform_raw.broker_accreditation_prospect_broker_profile
