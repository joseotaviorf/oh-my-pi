DROP TABLE datalake_clean.zendesk_tickets

CREATE EXTERNAL TABLE datalake_clean.`zendesk_tickets`(
    `subject` string,
    `created_at` string,
    `description` string,
    `external_id` string,
    `type` string,
    `channel` string,
    `source` string,
    `updated_at` string,
    `problem_id` string,
    `due_at` string,
    `id` string,
    `assignee_id` string,
    `generated_timestamp` string,
    `raw_subject` string,
    `forum_topic_id` string,
    `custom_fields` string,
    `allow_channelback` string,
    `satisfaction_rating` string,
    `submitter_id` string,
    `priority` string,
    `collaborator_ids` string,
    `tags` string,
    `brand_id` string,
    `metric_set` string,
    `group_id` string,
    `organization_id` string,
    `recipient` string,
    `is_public` string,
    `has_incidents` string,
    `status` string,
    `requester_id` string)
PARTITIONED BY (
  `dt_extraction` string)
STORED AS PARQUET
LOCATION
  's3://5a-datalake/clean/zendesk/tickets/'
  ;

MSCK REPAIR TABLE datalake_clean.zendesk_tickets;