WITH table_metastore AS (
    SELECT DISTINCT
        layer,
        database_name,
        table_name,
        year,
        month,
        day
    FROM
        datalake_documentation_metrics_clean.columns_metastore
    WHERE
        MAKE_DATE(year, month, day) BETWEEN '{load_start_date}' AND '{load_end_date}'
), table_documentation AS (
    SELECT DISTINCT
        database_name,
        table_name,
        table_description,
        owner
    FROM
        datalake_documentation_metrics_clean.columns_documentation
    WHERE
        MAKE_DATE(year, month, day) BETWEEN '{load_start_date}' AND '{load_end_date}'
)
SELECT
    ms.layer,
    ms.database_name,
    ms.table_name,
    COALESCE(doc.owner != '', FALSE) AS has_owner,
    COALESCE(doc.table_description != '', FALSE) AS has_description,
    date(format_string('%d-%d-%d', ms.year, ms.month, ms.day)) as dt_ingested,
    ms.year,
    ms.month,
    ms.day
FROM
    table_metastore AS ms
LEFT JOIN
    table_documentation AS doc
        ON ms.database_name = doc.database_name
        AND ms.table_name = doc.table_name
