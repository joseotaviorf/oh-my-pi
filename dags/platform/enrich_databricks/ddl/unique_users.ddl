CREATE TABLE datalake_databricks.unique_users (
    id_user STRING,
    email STRING,
    is_active_user BOOLEAN,
    is_active_employee BOOLEAN,
    dt_created DATE,
    dt_updated DATE,
    dt_deleted DATE
) USING DELTA LOCATION "s3://5a-datalake-prod/databricks/unique_users"
