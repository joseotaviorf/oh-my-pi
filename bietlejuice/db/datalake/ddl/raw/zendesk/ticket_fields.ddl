drop table datalake_raw.zendesk_tickets_fields;

CREATE EXTERNAL TABLE datalake_raw.`zendesk_tickets_fields`(
  `id` string,
  `title` string,
  `raw_title` string,
  `collapsed_for_agents` string,
  `visible_in_portal` string,
  `description` string,
  `active` string,
  `raw_title_in_portal` string,
  `created_at` string,
  `type` string,
  `raw_description` string,
  `required` string,
  `editable_in_portal` string,
  `required_in_portal` string,
  `updated_at` string,
  `system_field_options` string,
  `removable` string,
  `regexp_for_validation` string,
  `position` string,
  `tag` string,
  `title_in_portal` string)
PARTITIONED BY (
  `dt` string)
ROW FORMAT SERDE
  'org.openx.data.jsonserde.JsonSerDe'
STORED AS INPUTFORMAT
  'org.apache.hadoop.mapred.TextInputFormat'
OUTPUTFORMAT
  'org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat'
LOCATION
  's3://5a-datalake/raw/zendesk/tickets_fields/'
  ;

msck repair table datalake_raw.zendesk_tickets_fields;