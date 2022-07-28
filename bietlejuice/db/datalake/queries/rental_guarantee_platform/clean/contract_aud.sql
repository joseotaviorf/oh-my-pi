SELECT
    id,
    company_id AS id_company,
    property_id AS id_property,
    contractuuid AS uuid_contract,
    monthly_value,
    activation_value,
    total_value,
    guarantee_value,
    status,
    createdby AS created_by,
    service_tax,
    contract_duration_months,
    version,
    rev,
    revend AS rev_end,
    revtype AS rev_type,
    company_id_mod AS mod_id_company,
    property_id_mod AS mod_id_property,
    monthly_value_mod AS mod_monthly_value,
    activation_value_mod AS mod_activation_value,
    total_value_mod AS mod_total_value,
    guarantee_value_mod AS mod_guarantee_value,
    contract_duration_months_mod AS mod_contract_duration_months,
    status_mod AS mod_status,
    contractuuid_mod AS mod_uuid_contract,
    createdby_mod AS mod_created_by,
    service_tax_mod AS mod_service_tax,
    sent_guarantee_term_at_mod AS mod_ts_sent_guarantee_term,
    sent_guarantee_term_at AS ts_sent_guarantee_term,
    created_at AS ts_created,
    year,
    month,
    day
FROM
    datalake_rental_guarantee_platform_raw.contract_aud
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}