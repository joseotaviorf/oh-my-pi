SELECT 
    id,
    alias AS id_alias,
    REGEXP_EXTRACT(message,'(bietlejuice\.[a-z0-9-_]+)') AS dag_name,
    REPLACE(REGEXP_EXTRACT(message,'(Task: [a-z0-9-_]+)'),'Task: ','') AS task_name,
    owner AS owned_by,
    report['acknowledged_by'] AS acknowledged_by,
    report['closed_by'] AS closed_by,
    status,
    is_seen,
    acknowledged AS is_acknowledged,
    snoozed AS is_snoozed,
    created_at AS ts_created,
    updated_at AS ts_updated,
    DATEADD(MICROSECOND,report['ack_time'],created_at) AS ts_acknowledged,
    DATEADD(MICROSECOND,report['close_time'],created_at) AS ts_closed,
    year,
    month,
    day
FROM
    datalake_opsgenie_raw.alerts
WHERE
    DATE(created_at) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')    