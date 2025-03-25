SELECT
    id,
    agent_id AS id_agent,
    program_id AS id_program,
    rev,
    revend as rev_end,
    revtype as rev_type,
    details,
    agent_mod AS mod_id_agent,
    agencies_mod AS mod_agencies,
    details_mod AS mod_details,
    created_at_mod AS mod_ts_created,
    updated_at_mod AS mod_ts_updated,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_big_agent_raw.enrollment_aud
