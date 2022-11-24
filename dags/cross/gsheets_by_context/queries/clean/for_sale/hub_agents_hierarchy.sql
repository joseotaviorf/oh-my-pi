SELECT
    CAST(id_agent AS BIGINT) AS id_agent,
    cpf,
    creci,
    full_name,
    quintoandar_email,
    personal_number,
    status,
    function_type,
    hub_region,
    manager
FROM
    datalake_gsheets_raw.hub_agents_hierarchy
