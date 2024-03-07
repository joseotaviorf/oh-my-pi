SELECT
    id,
    agency_id AS id_agency,
    agent_id AS id_agent,
    program_id AS id_program,
    house_external_id AS id_house_external,
    rev,
    revend as rev_end,
    revtype as rev_type,
    details,
    status,
    type,
    failure_count,
    agency_id_mod AS mod_id_agency,
    agent_id_mod AS mod_id_agent,
    program_id_mod AS mod_id_program,
    house_external_id_mod AS mod_id_house_external,   
    details_mod AS mod_details, 
    status_mod AS mod_status,
    type_mod AS mod_type,
    failure_count_mod AS mod_failure_count,
    created_at_mod AS mod_ts_created,  
    updated_at_mod AS mod_ts_updated,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_big_agent_raw.earnings_aud
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}
