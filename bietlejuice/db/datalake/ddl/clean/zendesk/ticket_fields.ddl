drop table if exists datalake_clean.zendesk_ticket_fields;
create external table if not exists datalake_clean.zendesk_ticket_fields (
    id_ticket_fields string,
    title string,
    description string,
    agent_description string,
    url_ticket_fields string,
    raw_title string,
    raw_title_in_portal string,
    raw_description string,
    custom_field_options string,
    is_removable string,
    is_position string,
    is_required string,
    type string,
    is_active string,
    is_collapsed_for_agents string,
    is_visible_in_portal string,
    is_required_in_portal string,
    is_editable_in_portal string,
    is_title_in_portal string,
    ts_created_local string,
    ts_created string,
    ts_updated string,
    ts_load string
)
partitioned by (
    dt_extracted string
)
stored as parquet
location 's3://5a-datalake/clean/zendesk/ticket_fields/';
