drop table if exists datalake_clean.ticket_metrics;
create external table if not exists datalake_clean.ticket_metrics (
    id_ticket_metrics string,
    url_ticket_metrics string,
    ts_minutes_first_calendar_resolution string,
    ts_minutes_first_business_resolution string,
    ts_requester_updated string,
    ts_solved string,
    assignee_stations string,
    ts_latest_comment_added string,
    reopens string,
    ts_minutes_full_calendar_resolution string,
    ts_minutes_full_business_resolution string,
    id_ticket string,
    replies string,
    ts_minutes_calendar_requester_wait string,
    ts_minutes_business_requester_wait string,
    ts_minutes_calendar_agent_wait string,
    ts_minutes_business_agent_wait string,
    ts_minutes_calendar_on_hold string,
    ts_minutes_business_on_hold string,
    group_stations string,
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