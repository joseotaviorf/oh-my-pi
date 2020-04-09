create external table if not exists datalake_clean.zendesk_custom_fields (
    id_ticket string,
    custom_fields string,
    ts_updated string
)
partitioned by (
    dt_extracted string
)
stored as parquet
location 's3://5a-datalake/clean/zendesk/custom_fields/';