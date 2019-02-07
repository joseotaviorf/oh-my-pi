with parse_fields as (
    select zt.id,
        f1.field,
        regexp_extract(f1.field, '.*{\\?"id\\?":(\d+)', 1) as field_id,
        nullif(regexp_extract(f1.field, '"value\\?":\\?"?([^\\?"|}]+)', 1), 'null') as value
    from datalake_clean.zendesk_tickets zt
    cross join unnest(regexp_extract_all(zt.custom_fields, '{[^}]+[^,]+[^{]+}')) as f1(field)
),
fields_map as (
    select f.id,
        map_agg(cf.raw_title, f.value) as cols
    from parse_fields f
    left join datalake_clean.zendesk_ticket_fields cf
       on cf.id = f.field_id
    group by f.id
),
cast_datetime as (
  select
   id,
   channel,
   date_parse(regexp_extract(description, 'Chat started: (\d+.\d+.\d+ \d+:\d+ \wM)', 1), '%Y-%m-%d %h:%i %p') as chat_started_at
  from datalake_clean.zendesk_tickets
  where channel = '"chat"'
),
last_rows as (
    select
        id,
        max(dt_extraction) as dt
    from datalake_clean.zendesk_tickets
    group by 1
),
c as (
    select
    cast(sk_house_listing as bigint) as sk_house_listing,
    cast(sk_client as bigint) as sk_client,
    cast(sk_contract as bigint) as sk_contract,
    cast(sk_owner as bigint) as sk_owner
  from datalake_clean.ods_fact_listing_rent_flows
  where sk_contract != '-1'
    and sk_client != '-1'
    and sk_owner != '-1'
    and sk_house_listing != '-1'
  group by 1, 2, 3, 4
),
tickets as (
    select
    t.id as sk_ticket,
    coalesce(cast(dhl.sk_house_listing as bigint), -1) as sk_house_listing,
    coalesce(cast(dc.sk_contract as bigint), -1) as sk_contract,
    coalesce(t.requester_id, '-1') as sk_zendesk_requester_user,
    coalesce(t.submitter_id, '-1') as sk_zendesk_submitter_user,
    coalesce(t.assignee_id, '-1') as sk_zendesk_assignee_user,
    cast(date_format(from_iso8601_timestamp(t.created_at), '%Y%m%d') as integer) as sk_created_date,
    cast(coalesce(date_format(from_iso8601_timestamp(nullif(cast(json_extract(t.metric_set, '$.solved_at') as varchar), 'null')), '%Y%m%d'), '-1') as integer) as sk_solved_date,
    cast(date_format(from_iso8601_timestamp(t.dt_extraction), '%Y%m%d') as integer) as sk_extraction_date,
    coalesce(date_format(date_parse(regexp_extract(description, 'Chat started: (\d+.\d+.\d+ \d+:\d+ \wM)', 1), '%Y-%m-%d %h:%i %p'), '%Y%m%d'), '-1') as sk_chat_started_date,
    coalesce(date_format(date_parse(regexp_extract(description, 'Chat started: (\d+.\d+.\d+ \d+:\d+ \wM)', 1), '%Y-%m-%d %h:%i %p'), '%H:%i'), '-1') as sk_chat_started_time,
    coalesce(cast(json_extract(cast(json_extract(t.metric_set, '$.reply_time_in_minutes') as varchar), '$.calendar') as varchar), '-1') as minutes_first_reply_time,
    coalesce(cast(json_extract(cast(json_extract(t.metric_set, '$.first_resolution_time_in_minutes') as varchar), '$.calendar') as varchar), '-1') as minutes_first_resolution_time,
    coalesce(cast(json_extract(cast(json_extract(t.metric_set, '$.requester_wait_time_in_minutes') as varchar), '$.calendar') as varchar), '-1') as minutes_requester_wait_time,
    coalesce(cast(json_extract(cast(json_extract(t.metric_set, '$.agent_wait_time_in_minutes') as varchar), '$.calendar') as varchar), '-1') as minutes_agent_wait_time,
    coalesce(cast(json_extract(cast(json_extract(t.metric_set, '$.on_hold_time_in_minutes') as varchar), '$.calendar') as varchar), '-1') as minutes_on_hold_time,
    coalesce(cast(json_extract(cast(json_extract(t.metric_set, '$.full_resolution_time_in_minutes') as varchar), '$.calendar') as varchar), '-1') as minutes_full_resolution_time,
    cast(json_extract(t.metric_set, '$.reopens') as varchar) as reopens,
    cast(json_extract(t.metric_set, '$.replies') as varchar) as replies,
    t.is_public as has_public_comments,
    t.status,
    current_timestamp as ts_load,
    t.dt_extraction
from datalake_clean.zendesk_tickets t
join last_rows lr
    on lr.id = t.id and lr.dt = t.dt_extraction
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
where t.channel != 'api'
)
select
    t.sk_ticket,
    coalesce(t.sk_house_listing, c1.sk_house_listing) as sk_house_listing,
    coalesce(t.sk_contract, c2.sk_contract) as sk_contract,
    coalesce(c2.sk_client, c1.sk_client) as sk_client,
    coalesce(c2.sk_owner, c1.sk_owner) as sk_owner,
    t.sk_zendesk_requester_user,
    t.sk_zendesk_submitter_user,
    t.sk_zendesk_assignee_user,
    t.sk_created_date,
    t.sk_solved_date,
    t.sk_extraction_date,
    t.sk_chat_started_date,
    t.sk_chat_started_time,
    t.minutes_first_reply_time,
    t.minutes_first_resolution_time,
    t.minutes_requester_wait_time,
    t.minutes_agent_wait_time,
    t.minutes_on_hold_time,
    t.minutes_full_resolution_time,
    t.reopens,
    t.replies,
    t.has_public_comments,
    t.status,
    t.ts_load
from tickets t
left join c c1
    on t.sk_contract = c1.sk_contract
left join c c2
    on t.sk_house_listing = c2.sk_house_listing
__WHERE_CLAUSE__