with stitch_data as (
    select
		*,
        -- bug caused by start delay of daylight saving time
		if((from_iso8601_timestamp(created_at) >= cast('2018-10-23 02:00:00 UTC' as timestamp) and 
	   		from_iso8601_timestamp(created_at) <= cast('2018-11-04 03:00:00 UTC' as timestamp)),
			from_iso8601_timestamp(created_at) at time zone 'GMT-3',
			from_iso8601_timestamp(created_at) at time zone 'Brazil/East') as ts_created_local,
    	row_number() over (partition by id, dt order by updated_at desc) as last_updated
    from datalake_raw.zendesk_users
    where dt = '{execution_date}'
)
select
    id as id_user,
    active as is_active,
    alias,
    details,
    email,
    phone,
    name,
    notes,
    url as url_user,
    chat_only,
    custom_role_id as id_custom_role,
    default_group_id as id_default_group,
    external_id as id_external,
    locale,
    locale_id as id_locale,
    moderator as is_moderator,
    only_private_comments as is_only_private_comments,
    organization_id as id_organization,
    permanently_deleted as is_permanently_deleted,
    report_csv as is_report_csv,
    restricted_agent as is_restricted_agent,
    role,
    role_type,
    shared as is_shared,
    shared_agent as is_shared_agent,
    shared_phone_number as is_shared_phone_number, 
    signature,
    suspended as is_suspended,
    tags,
    ticket_restriction,
    time_zone,
    two_factor_auth_enabled as is_two_factor_auth_enabled,
    user_fields,
    verified as is_verified,
    cast(from_iso8601_timestamp(last_login_at) as varchar) as ts_last_login,
    cast(from_iso8601_timestamp(created_at) as varchar) as ts_created,
    cast(ts_created_local as varchar) as ts_created_local,
    cast(from_iso8601_timestamp(updated_at) as varchar) as ts_updated,
    cast(now() as varchar) as ts_load
from stitch_data
where last_updated = 1;