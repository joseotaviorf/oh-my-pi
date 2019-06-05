drop table if exists datalake_raw.zendesk_ticket_fields;
create external table if not exists datalake_raw.zendesk_ticket_fields (
    id string,
    `_sdc_sequence` string,
    `_sdc_received_at` string,
    `_sdc_batched_at` string,
    `_sdc_table_version` string,
    active string,
    agent_description string,
    collapsed_for_agents string,
    created_at string,
    custom_field_options string,
    description string,
    editable_in_portal string,
    position string,
    raw_description string,
    raw_title string,
    raw_title_in_portal string,
    regexp_for_validation string,
    removable string,
    required string,
    required_in_portal string,
    sub_type_id string,
    system_field_options string,
    tag string,
    title string,
    title_in_portal string,
    type string,
    updated_at string,
    url string,
    visible_in_portal string
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
   -- temp
  's3://5a-datalake-leo-test/stitch/zendesk_ticket_fields/ticket_fields/';