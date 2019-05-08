with stitch_data as (
    select
		*,
        -- bug caused by start delay of daylight saving time
		if((from_iso8601_timestamp(created_at) >= cast('2018-10-23 02:00:00 UTC' as timestamp) and 
	   		from_iso8601_timestamp(created_at) <= cast('2018-11-04 03:00:00 UTC' as timestamp)),
			from_iso8601_timestamp(created_at) at time zone 'GMT-3',
			from_iso8601_timestamp(created_at) at time zone 'Brazil/East') as ts_created_local,
		regexp_extract(satisfaction_rating, '\{"score":"(\w+)".+', 1) as score,
		regexp_extract(via, '\{"channel":"(\w+)".+', 1) as channel,
    	row_number() over (partition by id, dt order by updated_at desc) as last_updated
    from stitch.tickets
    where regexp_extract(via, '\{"channel":"(\w+)".+', 1) is not null
		  and raw_subject != 'SCRUBBED'
		  and subject not like '%WhatsApp - Comunicado%'
		  and dt = '{execution_date}'
)
select 
    id as ticket_id, 
    satisfaction_rating,
    url as ticket_url,
    priority,
    score,
    raw_subject,
    subject,
    channel,
    tags,
    group_id,
    ticket_form_id, 
    requester_id,
    assignee_id,
    collaborator_ids,
    brand_id,
    submitter_id,
    custom_fields,
    status,
    has_incidents,
    type,
    allow_channelback,
    description,
    recipient,
    is_public,
    cast(from_iso8601_timestamp(created_at) as varchar) as ts_created,
    cast(ts_created_local as varchar) as ts_created_local,
    cast(from_iso8601_timestamp(updated_at) as varchar) as ts_updated,
    now() as ts_load
from stitch_data t
where last_updated = 1;