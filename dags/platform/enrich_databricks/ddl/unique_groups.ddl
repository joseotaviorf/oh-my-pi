CREATE TABLE datalake_databricks.unique_groups (
    id_group STRING,
    id_group_external STRING,
    display_name STRING,
    dt_created DATE,
    dt_updated DATE,
    dt_deleted DATE
) USING DELTA LOCATION "s3://5a-datalake-prod/enrich/databricks/unique_groups"
