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
    TRUE AS has_3p_access_control,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_brokers_supply_processor_raw.business_context_detail