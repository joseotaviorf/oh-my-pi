SELECT
    id,
    listing_id AS id_listing,
    file_id AS id_file,
    partner_id AS id_partner,
    lead_id AS id_lead,
    business_context,
    status,
    status_reason,
    version,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_brokers_supply_processor_raw.business_context_detail