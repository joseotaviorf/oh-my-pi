drop table if exists datalake_clean.zendesk_tickets;
create external table if not exists datalake_clean.zendesk_tickets (
    id_ticket string,
    satisfaction_rating string,
    url_ticket string,
    priority string, 
    score string,
    raw_subject string,
    subject string,  
    channel string,
    via string,
    tags string,
    id_group string,
    id_ticket_form string,
    id_requester string,
    id_assignee string,
    ids_collaborator string,
    id_brand string,
    id_submitter string,
    status string,
    custom_fields string,
    has_incidents string,
    type string,
    allow_channelback string,
    description string,
    recipient string,
    is_public string,
    ts_created string,
    ts_created_local string,
    ts_updated string,
    ts_load string
)
partitioned by (
    dt string
)
stored as parquet
location 's3://5a-datalake/clean/zendesk/';