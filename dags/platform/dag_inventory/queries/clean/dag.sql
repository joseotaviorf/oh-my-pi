SELECT
    dag,
    dag_location,
    cluster_configuration,
    criticality,
    sla_deadline_localtime,
    CAST(freshness_max_staleness_minutes AS INT) AS freshness_max_staleness_minutes,
    freshness_active_window_localtime,
    year,
    month,
    day
FROM
    datalake_dag_inventory_raw.dag
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}