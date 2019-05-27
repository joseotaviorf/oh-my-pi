drop table if exists datalake_clean.zendesk_group_memberships;
create external table if not exists datalake_clean.zendesk_group_memberships (    
    id_group_memberships string,
    url_group_memberships string,
    is_default string,
    id_group string,
    id_user string,
    ts_created string,
    ts_created_local string,
    ts_updated string,
    ts_load string
)
partitioned by (
    dt_extracted string
)
stored as parquet
    location 's3://5a-datalake/clean/zendesk/group_memberships/';