with stitch_data as (
    select
		*,
        -- bug caused by start delay of daylight saving time
		if((from_iso8601_timestamp(created_at) >= cast('2018-10-23 02:00:00 UTC' as timestamp) and 
	   		from_iso8601_timestamp(created_at) <= cast('2018-11-04 03:00:00 UTC' as timestamp)),
			from_iso8601_timestamp(created_at) at time zone 'GMT-3',
			from_iso8601_timestamp(created_at) at time zone 'Brazil/East') as ts_created_local,
    	row_number() over (partition by id, dt order by updated_at desc) as last_updated
    from stitch.tickets
    where regexp_extract(via, '\{"channel":"(\w+)".+', 1) is not null
		  and raw_subject != 'SCRUBBED'
		  and dt = '{}'
)
select 
    id as ticket_id, 
    satisfaction_rating,
    url as ticket_url,
    priority,
    regexp_extract(via, '\{"score":"(\w+)".+', 1) as score,
    raw_subject,
    subject,
    regexp_extract(via, '\{"channel":"(\w+)".+', 1) as channel,
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
    created_at as ts_created,
    ts_created_local,
    updated_at as ts_updated,
    now() as ts_load
from stitch_data t
where last_updated = 1