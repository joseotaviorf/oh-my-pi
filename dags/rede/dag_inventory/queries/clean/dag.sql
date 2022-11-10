SELECT
    dag,
    dag_location,
    cluster_configuration,
    year,
    month,
    day
FROM
    datalake_dag_inventory_raw.dag
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}