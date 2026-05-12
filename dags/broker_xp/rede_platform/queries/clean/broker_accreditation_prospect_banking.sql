SELECT
    id,
    prospect_id AS id_prospect,
    bank_code,
    agency,
    account_number,
    account_type,
    pix_key,
    year,
    month,
    day
FROM
    datalake_rede_platform_raw.broker_accreditation_prospect_banking
