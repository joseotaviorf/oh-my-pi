drop table if exists datalake_clean.zendesk_ticket_metrics;
create external table if not exists datalake_clean.zendesk_ticket_metrics (
    id_ticket_metrics string,
    url_ticket_metrics string,
    ts_requester_updated string,
    ts_solved string,
    assignee_stations string,
    ts_latest_comment_added string,
    reopens string,
    id_ticket string,
    replies string,
    group_stations string,
    minutes_reply_calendar string,
    minutes_reply_business string,
    minutes_first_resolution_calendar string,
    minutes_first_resolution_business string,
    minutes_full_resolution_calendar string,
    minutes_full_resolution_business string,
    minutes_requester_wait_calendar string,
    minutes_requester_wait_business string,
    minutes_agent_wait_calendar string, 
    minutes_agent_wait_business string, 
    minutes_on_hold_calendar string, 
    minutes_on_hold_business string,
    ts_initially_assigned string,
    ts_assignee_updated string,
    ts_assigned string,
    ts_created string,
    ts_created_local string,
    ts_updated string,
    ts_load string
)
partitioned by (
    dt_extracted string
)
stored as parquet
    location 's3://5a-datalake/clean/zendesk/ticket_metrics/'