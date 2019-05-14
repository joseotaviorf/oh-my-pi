drop table if exists datalake_clean.zendesk_groups;
create external table if not exists datalake_clean.zendesk_groups (
    id_group string,
    url_group string,
    name string,
    is_deleted string,
    ts_created_local string,
    ts_created string,
    ts_updated string,
    ts_load string
)
partitioned by (
    dt string
)
stored as parquet
location 's3://5a-datalake/clean/zendesk/groups/';