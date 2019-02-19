with distinct_data as (
	with row_n as (
	    select
	        t.*,
	        row_number() over (partition by id, dt order by updated_at desc) as rn
	    from datalake_raw.zendesk_tickets t
	    where replace(cast(json_extract(via, '$.channel') as varchar), '"') != 'api'
	)
	select
		*
	from row_n
	where rn = 1
)
select
    subject,
    created_at,
    description,
    external_id,
    type,
    replace(cast(json_extract(via, '$.channel') as varchar), '"') as channel,
    replace(cast(json_extract(via, '$.source') as varchar), '\') as source,
    updated_at,
    problem_id,
    due_at,
    id,
    assignee_id,
    generated_timestamp,
    raw_subject,
    forum_topic_id,
    regexp_extract_all(replace(custom_fields, '\'), '\{\\?"id\\?":"?\w+"?, ?\\?"value\\?":"?.*?"?\}') as custom_fields,
    allow_channelback,
    satisfaction_rating,
    submitter_id,
    priority,
    regexp_extract_all(collaborator_ids, 'i":"([^"]+)', 1) as collaborator_ids ,
    regexp_extract_all(tags, '(?!"i"|","|":")"([^"]+)"', 1) as tags,
    brand_id,
    metric_set,
    group_id,
    organization_id,
    recipient,
    is_public,
    has_incidents,
    status,
    requester_id
from distinct_data