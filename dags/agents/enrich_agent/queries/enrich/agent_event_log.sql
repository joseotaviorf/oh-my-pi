SELECT
    id AS id_event_log,
    id_agent,
    id_capability,
    author_identifier AS id_author_user,
    author_type,
    author_role,
    channel,
    reason,
    on_behalf_of_role,
    event_type,
    ts_created,
    ts_updated,
    YEAR(ts_updated) AS year,
    MONTH(ts_updated) AS month,
    DAY(ts_updated) AS day
FROM
    datalake_ebdb_clean.agent_event_log
WHERE
    DATE(ts_updated) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
