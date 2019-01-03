with parse_fields as (
    select zt.id,
        cf.raw_title,
        regexp_extract(f1.field, 'id\\":(\d+).*value\\":([^}]+)', 2) as value
    from datalake_clean.zendesk_tickets zt
    cross join unnest(regexp_extract_all(zt.custom_fields, '{[^}]+[^,]+[^{]+}')) as f1(field)
    left join datalake_clean.zendesk_ticket_fields as cf
        on cast(cf.id as varchar) = regexp_extract(f1.field, 'id\\":(\d+).*value\\":([^}]+)', 1)
),
fields_map as (
    select id,
        map_agg(raw_title, regexp_extract(value, '\d+')) as cols
    from parse_fields
    group by id
)
select
    t.id as sk_ticket,
    coalesce(cast(dhl.sk_house_listing as bigint), -1) as sk_house_listing,
    coalesce(cast(dc.sk_contract as bigint), -1) as sk_contract,
    cast(date_format(from_iso8601_timestamp(t.created_at), '%Y%m%d') as integer) as sk_created_date,
    cast(coalesce(date_format(from_iso8601_timestamp(nullif(cast(json_extract(t.metric_set, '$.solved_at') as varchar), 'null')), '%Y%m%d'), '-1') as integer) as sk_solved_date,
    coalesce(cast(json_extract(cast(json_extract(t.metric_set, '$.reply_time_in_minutes') as varchar), '$.calendar') as varchar), '-1') as minutes_first_reply_time,
    coalesce(cast(json_extract(cast(json_extract(t.metric_set, '$.first_resolution_time_in_minutes') as varchar), '$.calendar') as varchar), '-1') as minutes_first_resolution_time,
    coalesce(cast(json_extract(cast(json_extract(t.metric_set, '$.requester_wait_time_in_minutes') as varchar), '$.calendar') as varchar), '-1') as minutes_requester_wait_time,
    coalesce(cast(json_extract(cast(json_extract(t.metric_set, '$.agent_wait_time_in_minutes') as varchar), '$.calendar') as varchar), '-1') as minutes_agent_wait_time,
    coalesce(cast(json_extract(cast(json_extract(t.metric_set, '$.on_hold_time_in_minutes') as varchar), '$.calendar') as varchar), '-1') as minutes_on_hold_time,
    coalesce(cast(json_extract(cast(json_extract(t.metric_set, '$.full_resolution_time_in_minutes') as varchar), '$.calendar') as varchar), '-1') as minutes_full_resolution_time,
    t.requester_id,
    t.submitter_id,
    coalesce(t.assignee_id, '-1') as assignee_id,
    cast(json_extract(t.metric_set, '$.reopens') as varchar) as reopens,
    cast(json_extract(t.metric_set, '$.replies') as varchar) as replies,
    t.is_public as has_public_comments,
    t.status,
    current_timestamp as ts_load
from datalake_clean.zendesk_tickets t
left join fields_map c
    on c.id = t.id
left join datalake_clean.ods_dim_house_listing dhl
     on c.cols['Código do Imóvel'] = dhl.short_id_house
        and cast(from_iso8601_timestamp(t.created_at) as timestamp)
        between cast(regexp_extract(dhl.ts_listing_version_start, '\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}') as timestamp)
         and (case
                when dhl.ts_listing_version_end = ''
                  then now()
                else cast(regexp_extract(dhl.ts_listing_version_end, '\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}') as timestamp)
              end)
left join datalake_clean.ods_dim_contract dc
    on c.cols['Código do Contrato'] = dc.sk_contract