with stitch_data as (
    select
		*,
        -- bug caused by start delay of daylight saving time
		if((from_iso8601_timestamp(created_at) >= cast('2018-10-23 02:00:00 UTC' as timestamp) and 
	   		from_iso8601_timestamp(created_at) <= cast('2018-11-04 03:00:00 UTC' as timestamp)),
			from_iso8601_timestamp(created_at) at time zone 'GMT-3',
			from_iso8601_timestamp(created_at) at time zone 'Brazil/East') as ts_created_local,
		cast(json_extract(via, '$.channel') as varchar) as ticket_via,
    	row_number() over (partition by id, dt order by updated_at desc) as last_updated
    from datalake_raw.zendesk_tickets
    where cast(json_extract(via, '$.channel') as varchar) is not null
		  and raw_subject != 'SCRUBBED'
		  and dt = '{execution_date}'
)
select 
    id as id_ticket, 
    satisfaction_rating,
    url as url_ticket,
    priority,
    raw_subject,
    subject,
    ticket_via,
    via,
    tags,
    group_id as id_group,
    ticket_form_id as id_ticket_form, 
    requester_id as id_requester,
    assignee_id as id_assignee,
    collaborator_ids as ids_collaborator,
    brand_id as id_brand,
    submitter_id as id_submitter,
    status,
    custom_fields,
    has_incidents,
    type,
    allow_channelback,
    description,
    recipient,
    is_public,
    cast(from_iso8601_timestamp(created_at) as varchar) as ts_created,
    cast(ts_created_local as varchar) as ts_created_local,
    cast(from_iso8601_timestamp(updated_at) as varchar) as ts_updated,
    cast(now() as varchar) as ts_load
from stitch_data
where last_updated = 1;