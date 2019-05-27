drop table if exists datalake_clean.zendesk_users;
create external table if not exists datalake_clean.zendesk_users (
    id_user string,
    is_active string,
    alias string,
    details string,
    email string,
    phone string,
    name string,
    notes string,
    url_user string,
    chat_only string,
    id_custom_role string,
    id_default_group string,
    id_external string,
    locale string,
    id_locale string,
    is_moderator string,
    is_only_private_comments string,
    id_organization string,
    is_permanently_deleted string,
    is_report_csv string,
    is_restricted_agent string,
    role string,
    role_type string,
    is_shared string,
    is_shared_agent string,
    is_shared_phone_number string, 
    signature string,
    is_suspended string,
    tags string,
    ticket_restriction string,
    time_zone string,
    is_two_factor_auth_enabled string,
    user_fields string,
    is_verified string,
    ts_last_login string,
    ts_created string,
    ts_created_local string,
    ts_updated string,
    ts_load string
)
partitioned by (
    dt_extracted string
)
stored as parquet
location 's3://5a-datalake/clean/zendesk/users/';