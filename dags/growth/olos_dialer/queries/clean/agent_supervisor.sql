SELECT
    AgentId AS id_agent,
    SupervisorId AS id_supervisor,
    year,
    month,
    day
FROM
    datalake_olos_dialer_raw.AgentSupervisor
WHERE
    MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
