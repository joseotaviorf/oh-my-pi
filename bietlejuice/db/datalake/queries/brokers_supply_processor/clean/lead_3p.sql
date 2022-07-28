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
    enrichment_reason,
    discard_reason,
    eligible_reason,
    cnpj,
    status,
    version,
    eligible AS is_eligible,
    sent_to_bob AS is_sent_to_bob,
    enriched AS is_enriched,
    discard AS is_discarded,
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
