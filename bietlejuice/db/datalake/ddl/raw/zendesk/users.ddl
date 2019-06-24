drop table if exists datalake_raw.zendesk_users;
create external table if not exists datalake_raw.zendesk_users (
    id string,
    active string,
    /* These columns are applicable to all tables and integration types. 
       Unless noted, every column in this list will be present in every integration table created by Stitch. */
    `_sdc_sequence` string,       -- order in which data points were considered for loading.
    `_sdc_received_at` string,    -- indicating when Stitch received the record for loading.
    `_sdc_batched_at` string,     -- indicating when Stitch loaded the batch the record was a part of into the data warehouse
    `_sdc_table_version` string,  -- Indicates the version of the table.
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
  's3://5a-datalake/raw/zendesk_users/users/';