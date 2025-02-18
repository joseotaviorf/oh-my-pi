SELECT
    id,
    agency_id AS id_agency,
    program_id AS id_program,
    external_domain_id AS id_external_domain,
    external_receiver_id AS id_external_receiver,
    status,
    type,
    failure_count,
    details,
    remuneration_value,    
    external_domain_type,    
    external_receiver_type,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_big_agent_raw.earnings
WHERE
    MAKE_DATE(year, month, day) BETWEEN '{load_start_date}' AND '{load_end_date}'
