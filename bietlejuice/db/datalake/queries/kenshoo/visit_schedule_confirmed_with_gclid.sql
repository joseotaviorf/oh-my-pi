with amplitude_schedules as (
	select
		ts_event as "Date",
		case
			when json_extract_scalar(user_properties, '$.gclid') is not null then '_k_' || json_extract_scalar(user_properties, '$.gclid') || '_k_'
		end as "GCLID"
		-- Appending _k_ so kenshoo client can decode as google client id
	from
		{db}.{table_name}
	where
		event_type = 'visit_schedule_confirmed'
		and json_extract_scalar(user_properties, '$.utm_source') = 'google'
		and json_extract_scalar(user_properties, '$.utm_medium') = 'cpc'
		and date(ts_event) = date('{dt}')
)
select
    "Date",
     "GCLID",
     'visit_schedule_confirmed_amp' as "Conversion Type",
      1 as "Qty."
from amplitude_schedules
where "GCLID" is not null
