with distinct_users as (
	select 
		id_user, 
		max(ts_last_login) as ts_last_login, 
		max(ts_updated) as ts_updated
	from datalake_clean.zendesk_users
	where dt_extracted='{partition_date}'
	group by 1
)
select
    cast(u.id_user as bigint) as sk_zendesk_user,
    cast(u.is_active as boolean) as is_active,
    u.url_user,
    u.name,
    u.alias,
    u.email,
    u.phone,
    cast(u.is_shared_phone_number as boolean) as is_shared_phone_number,
    u.time_zone,
    u.locale,
    cast(u.id_organization as integer) as id_organization,
    cast(u.is_verified as boolean) as is_verified,
    cast(u.id_external as integer) as id_external,
    u.tags,
    u.role,
    cast(u.id_default_group as integer) as id_group,
    cast(u.ts_last_login as timestamp) as ts_last_login,
    cast(u.ts_created as timestamp) as ts_created,
    cast(u.ts_created_local as timestamp) as ts_created_local,
    cast(u.ts_updated as timestamp) as ts_updated,
    now() as ts_load
from distinct_users du
inner join datalake_clean.zendesk_users u
on u.id_user=du.id_user and u.ts_updated=du.ts_updated;
