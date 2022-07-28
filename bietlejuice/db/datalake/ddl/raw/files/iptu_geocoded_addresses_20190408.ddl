CREATE TABLE datalake_files_raw.iptu_geocoded_addresses_20190408 (
    lat double,
    lng double,
    bldg_address_id string,
    geocoded_address string,
    iptu_formatted_address string
)
USING com.databricks.spark.csv
OPTIONS (
    path "s3://datalake.s3.data.quintoandar.com.br/raw/files/iptu/geocoded_addresses_20190408.csv",
    header "true"
)
