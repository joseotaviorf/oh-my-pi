SELECT
    id,
    rev,
    revtype AS rev_type,
    revend AS rev_end,
    house_id AS id_house,
    business_context,
    status,
    house_id_mod AS mod_id_house,
    business_context_mod AS mod_business_context,
    status_mod AS mod_status,
    created_at_mod AS mod_ts_created,
    updated_at_mod AS mod_ts_updated,
    TIMESTAMP(created_at) AS ts_created,
    TIMESTAMP(updated_at) AS ts_updated,
    year,
    month,
    day    
FROM
    datalake_big_agent_raw.listing_aud