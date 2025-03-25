SELECT
    id,
    rev,
    revend as rev_end,
    revtype as rev_type,
    metadata AS details,
    agencies_mod AS mod_agencies,
    metadata_mod AS mod_details,
    created_at_mod AS mod_ts_created,
    updated_at_mod AS mod_ts_updated,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_big_agent_raw.house_aud