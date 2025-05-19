SELECT
    id,
    listing_id AS id_listing,
    file_id AS id_file,
    partner_id AS id_partner,
    business_context,
    status,
    status_reason,
    version,
    rev,
    revend AS rev_end,
    revtype AS rev_type,
    listing_id_mod AS mod_id_listing,
    file_id_mod AS mod_id_file,
    partner_id_mod AS mod_id_partner,
    business_context_mod AS mod_business_context,
    status_mod AS mod_status,
    status_reason_mod AS mod_status_reason,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_brokers_supply_processor_raw.business_context_detail_aud
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}
