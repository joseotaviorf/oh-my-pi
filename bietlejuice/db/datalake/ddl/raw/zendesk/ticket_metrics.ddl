drop table if not exists datalake_raw.zendesk_ticket_metrics;
create external table if exists datalake_raw.zendesk_ticket_metrics (
    id string,
    `_sdc_sequence` string,
    `_sdc_received_at` string,
    `_sdc_batched_at` string,
    `_sdc_table_version` string,
    first_resolution_time_in_minutes string,
    requester_updated_at string,
    solved_at string,
    reply_time_in_minutes string,
    url string,
    status_updated_at string,
    assignee_stations string,
    latest_comment_added_at string,
    updated_at string,
    reopens string,
    full_resolution_time_in_minutes string,
    ticket_id string,
    created_at string,
    replies string,
    requester_wait_time_in_minutes string,
    agent_wait_time_in_minutes string,
    on_hold_time_in_minutes string,
    group_stations string,
    initially_assigned_at string,
    assignee_updated_at string,
    assigned_at string
)
partitioned by (
    dt string
)
ROW FORMAT SERDE                                                                                                                                                                                                                                               
  'org.openx.data.jsonserde.JsonSerDe'                                                                                                                                                                                                                         
STORED AS INPUTFORMAT                                                                                                                                                                                                                                          
  'org.apache.hadoop.mapred.TextInputFormat'                                                                                                                                                                                                                   
OUTPUTFORMAT                                                                                                                                                                                                                                                   
  'org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat'                                                                                                                                                                                                 
LOCATION
    's3://5a-datalake-leo-test/stitch/zendesk/ticket_metrics';                   
