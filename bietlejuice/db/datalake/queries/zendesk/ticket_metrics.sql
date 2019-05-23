with stitch_data as (
    select
		tm.*,
        -- bug caused by start delay of daylight saving time
		if((from_iso8601_timestamp(tm.created_at) >= cast('2018-10-23 02:00:00 UTC' as timestamp) and 
	   		from_iso8601_timestamp(tm.created_at) <= cast('2018-11-04 03:00:00 UTC' as timestamp)),
			from_iso8601_timestamp(tm.created_at) at time zone 'GMT-3',
			from_iso8601_timestamp(tm.created_at) at time zone 'Brazil/East') as ts_created_local,
    	row_number() over (partition by tm.id, tm.dt order by tm.updated_at desc) as last_updated
    from stitch.ticket_metrics tm
    left join stitch.tickets t
    on t.id = tm.ticket_id
    where tm.dt = '{execution_date}'
          and regexp_extract(t.via, '."channel":"(\w+)".+', 1) is not null
		  and t.raw_subject != 'SCRUBBED'
)
select
    id as id_ticket_metrics,
    url as url_ticket_metrics,
    cast(from_iso8601_timestamp(requester_updated_at) as varchar) as ts_requester_updated,
    cast(from_iso8601_timestamp(solved_at) as varchar) as ts_solved,
    assignee_stations,
    cast(from_iso8601_timestamp(latest_comment_added_at) as varchar) as ts_latest_comment_added,
    reopens,
    ticket_id as id_ticket,
    replies,
    group_stations,
    cast(json_extract(reply_time_in_minutes,'$.calendar') as varchar) as minutes_reply_calendar,
    cast(json_extract(reply_time_in_minutes,'$.business') as varchar) as minutes_reply_business,
    cast(json_extract(first_resolution_time_in_minutes,'$.calendar') as varchar) as minutes_first_resolution_calendar,
    cast(json_extract(first_resolution_time_in_minutes,'$.business') as varchar) as minutes_first_resolution_business,
    cast(json_extract(full_resolution_time_in_minutes,'$.calendar') as varchar) as minutes_full_resolution_calendar,
    cast(json_extract(full_resolution_time_in_minutes,'$.business') as varchar) as minutes_full_resolution_business,
    cast(json_extract(requester_wait_time_in_minutes,'$.calendar') as varchar) as minutes_requester_wait_calendar,
    cast(json_extract(requester_wait_time_in_minutes,'$.business') as varchar) as minutes_requester_wait_business,
    cast(json_extract(agent_wait_time_in_minutes,'$.calendar') as varchar) as minutes_agent_wait_calendar,
    cast(json_extract(agent_wait_time_in_minutes,'$.business') as varchar) as minutes_agent_wait_business,
    cast(json_extract(on_hold_time_in_minutes,'$.calendar') as varchar) as minutes_on_hold_calendar,
    cast(json_extract(on_hold_time_in_minutes,'$.business') as varchar) as minutes_on_hold_business,
    cast(from_iso8601_timestamp(initially_assigned_at) as varchar) as ts_initially_assigned,
    cast(from_iso8601_timestamp(assignee_updated_at) as varchar) as ts_assignee_updated,
    cast(from_iso8601_timestamp(assigned_at) as varchar) as ts_assigned,
    cast(from_iso8601_timestamp(created_at) as varchar) as ts_created,
    cast(ts_created_local as varchar) as ts_created_local,
    cast(from_iso8601_timestamp(updated_at) as varchar) as ts_updated,
    cast(now() as varchar) as ts_load
from stitch_data
where last_updated = 1;