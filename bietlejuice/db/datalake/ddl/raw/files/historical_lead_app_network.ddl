-- This table file was manually created in datalake
CREATE TABLE datalake_static_files_raw.historical_lead_app_network (
    user_id string,
    network string
)
USING com.databricks.spark.csv
OPTIONS (
    path "s3://datalake.s3.data.quintoandar.com.br/raw/files/historical_lead_app_network/historical_lead_app_network.csv",
    header "true"
)
