WITH aggregated_dag_info AS (
    SELECT
        database_name,
        collect_set(owner) AS owners,
        collect_set(has_lineage_from_product) AS has_lineage_from_product
    FROM
        datalake_documentation_metrics_clean.dag_metadata
    WHERE
        year = {year}
        AND month = {month}
        AND day = {day}
    GROUP BY
        database_name
), dag_info AS (
    SELECT
        database_name,
        array_join(owners, ", ") AS owners,
        CASE
            WHEN size(has_lineage_from_product) > 1 THEN null
            ELSE has_lineage_from_product[0]
        END AS has_lineage_from_product
    FROM
        aggregated_dag_info
), tables_metastore AS (
    SELECT
        layer,
        database_name,
        table_name,
        year,
        month,
        day
    FROM
        datalake_documentation_metrics_clean.columns_metastore
    WHERE
        year = {year}
        AND month = {month}
        AND day = {day}
    GROUP BY
        layer,
        database_name,
        table_name,
        year,
        month,
        day
), lineage_and_tags AS (
    SELECT
        database_name,
        table_name,
        has_lineage,
        has_tags
    FROM
        datalake_documentation_metrics_clean.lineage_and_tags
    WHERE
        year = {year}
        AND month = {month}
        AND day = {day}
)
SELECT
    ms.layer,
    ms.database_name,
    ms.table_name,
    di.owners,
    COALESCE(md.has_lineage, di.has_lineage_from_product, False) as has_lineage,
    COALESCE(md.has_tags, False) as has_tags,
    ms.year,
    ms.month,
    ms.day
FROM
    tables_metastore AS ms
LEFT JOIN
    lineage_and_tags as md
        ON ms.database_name = md.database_name
        AND ms.table_name = md.table_name
LEFT JOIN
    dag_info AS di
        ON ms.database_name = di.database_name