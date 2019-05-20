with stitch_data as (
    select
		*,
        -- bug caused by start delay of daylight saving time
		if((from_iso8601_timestamp(created_at) >= cast('2018-10-23 02:00:00 UTC' as timestamp) and 
	   		from_iso8601_timestamp(created_at) <= cast('2018-11-04 03:00:00 UTC' as timestamp)),
			from_iso8601_timestamp(created_at) at time zone 'GMT-3',
			from_iso8601_timestamp(created_at) at time zone 'Brazil/East') as ts_created_local,
    	row_number() over (partition by id, dt order by updated_at desc) as last_updated
    from stitch.group_memberships
    where dt = '{execution_date}'
)
select
    id as id_group_memberships,
    url as url_group_memberships,
    default as is_default,     
    group_id as id_group,
    user_id as id_user,
    cast(from_iso8601_timestamp(created_at) as varchar) as ts_created,
    cast(ts_created_local as varchar) as ts_created_local,
    cast(from_iso8601_timestamp(updated_at) as varchar) as ts_updated,
    cast(now() as varchar) as ts_load
from stitch_data
where last_updated = 1;