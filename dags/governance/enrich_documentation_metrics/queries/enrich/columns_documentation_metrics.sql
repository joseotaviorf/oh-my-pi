WITH columns_metastore AS (
    SELECT
        layer,
        database_name,
        table_name,
        column_name,
        year,
        month,
        day
    FROM
        datalake_documentation_metrics_clean.columns_metastore
    WHERE
        MAKE_DATE(year, month, day) BETWEEN '{load_start_date}' AND '{load_end_date}'
), columns_documentation AS (
    SELECT
        database_name,
        table_name,
        column_name,
        column_description,
        joins_with_column
    FROM
        datalake_documentation_metrics_clean.columns_documentation
    WHERE
        MAKE_DATE(year, month, day) BETWEEN '{load_start_date}' AND '{load_end_date}'
)
SELECT
    ms.layer,
    ms.database_name,
    ms.table_name,
    ms.column_name,
    COALESCE(doc.column_description != '', FALSE) AS has_description,
    COALESCE(doc.joins_with_column != '', FALSE) AS has_joins_with_column,
    date(format_string('%d-%d-%d', ms.year, ms.month, ms.day)) as dt_ingested,
    ms.year,
    ms.month,
    ms.day
FROM
    columns_metastore AS ms
LEFT JOIN
    columns_documentation AS doc
        ON ms.database_name = doc.database_name
        AND ms.table_name = doc.table_name
        AND ms.column_name = doc.column_name
