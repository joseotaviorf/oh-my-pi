drop table datalake_clean.zendesk_ticket_fields;

CREATE EXTERNAL TABLE datalake_clean.`zendesk_ticket_fields`(
    `id` string,
    `title` string,
    `raw_title` string,
    `is_collapsed_for_agents` string,
    `is_visible_in_portal` string,
    `description` string,
    `is_active` string,
    `raw_title_in_portal` string,
    `created_at` string,
    `type` string,
    `raw_description` string,
    `is_required` string,
    `is_editable_in_portal` string,
    `is_required_in_portal` string,
    `updated_at` string,
    `system_field_options` string,
    `is_removable` string,
    `validation_regexp` string,
    `position` string,
    `tag` string,
    `title_in_portal` string)
PARTITIONED BY (
  `dt_extraction` string)
ROW FORMAT SERDE
  'org.openx.data.jsonserde.JsonSerDe'
STORED AS PARQUET
LOCATION
  's3://5a-datalake/clean/zendesk/tickets_fields/'
  ;

msck repair table datalake_clean.zendesk_ticket_fields;