SELECT
    id,
    lead_uuid AS uuid_lead,
    NULL::BIGINT AS id_real_estate,
    id_by_real_estate,
    company_uuid AS uuid_company,
    brokers,
    location,
    pricing,
    owner,
    blueprint,
    details,
    access,
    NULL::STRING AS administrators,
    owner_agent,
    photos,
    lead_hash,
    cnpj,
    sent_to_main AS is_sent_to_main,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_brokers_supply_processor_raw.lead3p
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}
