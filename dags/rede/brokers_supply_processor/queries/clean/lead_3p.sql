SELECT
    id,
    partner_id AS id_partner,
    file_id AS id_file,
    listing_id AS id_listing,
    lead_uuid AS uuid_lead,
    real_estate_id AS id_real_estate,
    id_by_real_estate,
    brokers,
    location,
    pricing,
    owner,
    blueprint,
    details,
    access,
    administrators,
    photos,
    lead_hash,
    status_reason,
    cnpj,
    status,
    version,
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
