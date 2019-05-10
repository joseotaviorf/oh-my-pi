drop table if exists datalake_clean.zendesk_tickets;
create external table if not exists datalake_clean.zendesk_tickets (
    ticket_id string,
    satisfaction_rating string,
    ticket_url string,
    priority string, 
    score string,
    raw_subject string,
    subject string,  
    channel string,
    via string,
    tags string,
    group_id string,
    ticket_form_id string,
    requester_id string,
    assignee_id string,
    collaborator_ids string,
    brand_id string,
    submitter_id string,
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