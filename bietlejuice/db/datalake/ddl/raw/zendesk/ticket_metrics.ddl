drop table if exists datalake_raw.zendesk_ticket_metrics;
create external table if not exists datalake_raw.zendesk_ticket_metrics (
    id string,
    /* These columns are applicable to all tables and integration types. 
       Unless noted, every column in this list will be present in every integration table created by Stitch. */
    `_sdc_sequence` string,      -- order in which data points were considered for loading.
    `_sdc_received_at` string,   -- indicating when Stitch received the record for loading.
    `_sdc_batched_at` string,    -- indicating when Stitch loaded the batch the record was a part of into the data warehouse
    `_sdc_table_version` string, -- Indicates the version of the table.
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
row format serde                                                                                                                                                                                                                                               
    'org.openx.data.jsonserde.JsonSerDe'                                                                                                                                                                                                                         
stored as inputformat                                                                                                                                                                                                                                          
    'org.apache.hadoop.mapred.TextInputFormat'                                                                                                                                                                                                                   
outputformat                                                                                                                                                                                                                                                   
    'org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat'                                                                                                                                                                                                 
location
    's3://5a-datalake/raw/zendesk_tickets/ticket_metrics';                   
