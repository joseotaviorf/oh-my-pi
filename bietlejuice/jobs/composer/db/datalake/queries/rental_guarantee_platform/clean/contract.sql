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
    sent_guarantee_term_at AS ts_sent_guarantee_term,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_rental_guarantee_platform_raw.contract
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}
