drop table if exists datalake_raw.zendesk_users;
create external table if not exists datalake_raw.zendesk_users (
    id string,
    active string,
    `_sdc_sequence` string,
    `_sdc_received_at` string,
    `_sdc_batched_at` string,
    `_sdc_table_version` string,
    alias string,
    chat_only string,
    created_at string,
    custom_role_id string,
    default_group_id string,
    details string,
    email string,
    external_id string,
    last_login_at string,
    locale string,
    locale_id string,
    moderator string,
    name string,
    notes string,
    only_private_comments string,
    organization_id string,
    permanently_deleted string,
    phone string,
    report_csv string,
    restricted_agent string,
    role string,
    role_type string,
    shared string,
    shared_agent string,
    shared_phone_number string,
    signature string,
    suspended string,
    tags string,
    ticket_restriction string,
    time_zone string,
    two_factor_auth_enabled string,
    updated_at string,
    url string,
    user_fields string,
    verified string
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
  's3://5a-datalake-leo-test/stitch/zendesk_users/users/';