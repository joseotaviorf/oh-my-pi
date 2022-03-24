SELECT
    agent_id AS id_agent,
    department,
    email,
    valid_department,
    TO_DATE(start_date, 'MM/dd/yyyy') AS dt_start,
    TO_DATE(end_date, 'MM/dd/yyyy') AS dt_end
FROM
    datalake_gsheets_raw.support_agents_department