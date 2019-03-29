with distinct_data as (
	with row_n as (
	    select
	        t.*,
	        row_number() over (partition by id, dt order by updated_at desc) as rn
	    from datalake_raw.zendesk_tickets t
	    __WHERE_CLAUSE__
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
    replace(replace(replace(json_format(json_extract(via, '$.source')), '"{\', '{'), '}"', '}'), '\', '') as source,
    updated_at,
    problem_id,
    due_at,
    id,
    assignee_id,
    generated_timestamp,
    raw_subject,
    forum_topic_id,
    '[' || replace(
    	replace(
    		replace(array_join(regexp_extract_all(
    			replace(custom_fields, '\'), '\{\\?"id\\?":"?\w+"?, ?\\?"value\\?":"?.*?"?\}'
    		), ','), '"{\', '{'
    	), '}"', '}'
    ), '\', '') || ']' as custom_fields,
    allow_channelback,
    satisfaction_rating,
    submitter_id,
    priority,
    replace(collaborator_ids, '"', '') as colaborator_ids,
    cast(regexp_extract_all(tags, '(?!"i"|","|":")"([^"]+)"', 1) as JSON) as tags,
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