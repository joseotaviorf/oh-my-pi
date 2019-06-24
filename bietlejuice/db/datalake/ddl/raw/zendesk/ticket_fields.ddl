drop table if exists datalake_raw.zendesk_ticket_fields;
create external table if not exists datalake_raw.zendesk_ticket_fields (
    id string,
    /* These columns are applicable to all tables and integration types. 
       Unless noted, every column in this list will be present in every integration table created by Stitch. */
    `_sdc_sequence` string,       -- order in which data points were considered for loading.
    `_sdc_received_at` string,    -- indicating when Stitch received the record for loading.
    `_sdc_batched_at` string,     -- indicating when Stitch loaded the batch the record was a part of into the data warehouse
    `_sdc_table_version` string,  -- Indicates the version of the table.
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
  's3://5a-datalake/raw/zendesk_ticket_fields/ticket_fields/';