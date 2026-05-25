CREATE TABLE datalake_databricks.unique_service_principals (
    id_service_principal STRING,
    id_service_principal_external STRING,
    display_name STRING,
    application_id STRING,
    is_active BOOLEAN,
    year INT,
    month INT,
    day INT
) USING DELTA LOCATION "s3://5a-datalake-prod/enrich/databricks/unique_service_principals"
