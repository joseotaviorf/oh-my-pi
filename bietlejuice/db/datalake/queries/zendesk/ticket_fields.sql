with stitch_data as (
    select
		*,
        -- bug caused by start delay of daylight saving time
		if((from_iso8601_timestamp(created_at) >= cast('2018-10-23 02:00:00 UTC' as timestamp) and 
	   		from_iso8601_timestamp(created_at) <= cast('2018-11-04 03:00:00 UTC' as timestamp)),
			from_iso8601_timestamp(created_at) at time zone 'GMT-3',
			from_iso8601_timestamp(created_at) at time zone 'Brazil/East') as ts_created_local,
    	row_number() over (partition by id, dt order by updated_at desc) as last_updated
    from datalake_raw.zendesk_ticket_fields
    where dt = '{execution_date}'
)
select
    id as id_ticket_fields,
    title,
    description,
    agent_description,
    url as url_ticket_fields,
    raw_title,
    raw_title_in_portal,
    raw_description,
    custom_field_options,
    removable as is_removable,
    position as is_position,
    required as is_required,
    type,
    active as is_active,
    collapsed_for_agents as is_collapsed_for_agents,
    visible_in_portal as is_visible_in_portal,
    required_in_portal as is_required_in_portal,
    editable_in_portal as is_editable_in_portal,
    title_in_portal as is_title_in_portal,
    ts_created_local,
    cast(from_iso8601_timestamp(created_at) as varchar) as ts_created,
    cast(from_iso8601_timestamp(updated_at) as varchar) as ts_updated,
    cast(now() as varchar) as ts_load
from stitch_data
where last_updated = 1;


