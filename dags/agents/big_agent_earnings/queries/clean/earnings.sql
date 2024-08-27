SELECT
    id,
    agency_id AS id_agency,
    agent_id AS id_agent,
    program_id AS id_program,
    house_external_id AS id_house_external,
    status,
    type,
    failure_count,
    details,
    remuneration_value,
    external_domain_id,
    external_domain_type,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_big_agent_raw.earnings
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}