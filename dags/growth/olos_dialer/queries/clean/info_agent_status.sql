SELECT
    AgentStatusId AS id_disposition,
    Description AS description,
    year,
    month,
    day
FROM
    datalake_olos_dialer_raw.Info_AgentStatus
WHERE
    MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')