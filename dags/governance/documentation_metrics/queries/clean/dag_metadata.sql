SELECT
    layer,
    dag_name,
    database_name,
    has_lineage_from_product,
    owner,
    year,
    month,
    day
FROM
    datalake_documentation_metrics_raw.dag_metadata
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}
