drop table if exists datalake_raw.zendesk_tickets;
create external table if not exists datalake_raw.zendesk_tickets (
    id string,
    generated_timestamp string,
    `_sdc_sequence` string,
    `_sdc_received_at` string,
    `_sdc_batched_at` string,
    `_sdc_table_version` string,
    satisfaction_rating string,
    url string,
    priority string,
    raw_subject string,
    via string,
    sharing_agreement_ids string,
    group_id string,
    tags string,
    allow_attachments string,
    follower_ids string,
    ticket_form_id string,
    is_public string,
    updated_at string,
    email_cc_ids string,
    status string,
    custom_fields string,
    subject string,
    has_incidents string,
    brand_id string,
    type string,
    created_at string,
    collaborator_ids string,
    requester_id string,
    allow_channelback string,
    followup_ids string,
    submitter_id string,
    description string,
    assignee_id string,
    recipient string
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
  's3://5a-datalake-leo-test/stitch/zendesk/tickets'