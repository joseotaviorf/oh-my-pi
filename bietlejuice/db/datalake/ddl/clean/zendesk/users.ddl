drop table datalake_clean.zendesk_users;

CREATE EXTERNAL TABLE datalake_clean.`zendesk_users`(
    id string,
    url string,
    name string,
    email string,
    created_at string,
    updated_at string,
    time_zone string,
    iana_time_zone string,
    phone string,
    shared_phone_number string,
    photo string,
    locale_id string,
    locale string,
    organization_id string,
    role string,
    verified string,
    external_id string,
    tags string,
    alias string,
    active string,
    shared string,
    shared_agent string,
    last_login_at string,
    two_factor_auth_enabled string,
    signature string,
    details string,
    notes string,
    role_type string,
    custom_role_id string,
    moderator string,
    ticket_restriction string,
    only_private_comments string,
    restricted_agent string,
    suspended string,
    chat_only string,
    default_group_id string,
    report_csv string,
    user_fields string)
PARTITIONED BY (
  `dt` string)
STORED AS PARQUET
LOCATION
  's3://5a-datalake/clean/zendesk/users/'
;

msck repair table datalake_clean.zendesk_users;