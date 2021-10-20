SELECT
    layer,
    database_name,
    table_name,
    has_lineage,
    has_tags,
    year,
    month,
    day
FROM
    datalake_documentation_metrics_raw.lineage_and_tags_metrics
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}
