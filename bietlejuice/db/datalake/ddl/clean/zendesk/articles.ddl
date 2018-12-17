DROP TABLE datalake_clean.zendesk_articles;

CREATE EXTERNAL TABLE datalake_clean.`zendesk_articles`(
  `id` string,
  `url` string,
  `html_url` string,
  `author_id` string,
  `comments_disabled` string,
  `draft` string,
  `promoted` string,
  `position` string,
  `vote_sum` string,
  `vote_count` string,
  `section_id` string,
  `created_at` string,
  `updated_at` string,
  `name` string,
  `title` string,
  `source_locale` string,
  `locale` string,
  `outdated` string,
  `outdated_locales` string,
  `edited_at` string,
  `user_segment_id` string,
  `permission_group_id` string,
  `label_names` string,
  `body` string)
PARTITIONED BY (
  `dt_extraction` string)
STORED AS PARQUET
LOCATION
  's3://5a-datalake/clean/zendesk/articles/';

MSCK REPAIR TABLE datalake_clean.zendesk_articles;