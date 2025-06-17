SELECT
    id AS id_alert,
    alias AS id_alias,
    tinyId AS id_tiny,
    message,
    entity,
    source,
    status,
    tags,
    integrationType AS integration_type,
    integrationName AS integration_name,
    count,
    owner,
    priority,
    responders,
    actions,
    snoozed AS is_snoozed,
    seen AS is_seen,
    acknowledged AS is_acknowledged,
    TIMESTAMP(lastOccuredAt) AS ts_last_occured,
    TIMESTAMP(createdAt) AS ts_created,
    TIMESTAMP(updatedAt) AS ts_updated,
    dt_load,
    year,
    month,
    day
FROM
    datalake_jira_ops_raw.alerts
WHERE
    MAKE_DATE(year, month, day) BETWEEN "{load_start_date}" AND "{load_end_date}"
