with tickets_filter as (
	select distinct t.*
    from datalake_clean.zendesk_tickets t
	where (t.ticket_via<>'api' or (t.ticket_via='api' and t.tags not like '%hsm%'))
	and t.dt_extracted='{extraction_date}'
),
last_updated_ticket as (
    select id_ticket, max(ts_updated) as ts_updated from tickets_filter group by 1
),
last_updated_group as (
    select id_group, max(ts_updated) as ts_updated from datalake_clean.zendesk_groups group by 1
),
groups as (
    select
        g.id_group,
        g.name,
        g.url_group
    from datalake_clean.zendesk_groups g
    inner join last_updated_group ge
    on ge.id_group = g.id_group and ge.ts_updated = g.ts_updated
    group by 1,2,3
)
select
    cast(t.id_ticket as bigint) as sk_ticket,
    t.subject,
    t.description,
    t.ticket_via,
    case
        when t.ticket_via in ('api', 'web') and (tags like '%call_contato_ativo%' or tags like '%call_contato_receptivo%') then 'call'
        when t.ticket_via in ('api') and tags like '%form%' then 'form_faq'
        when t.ticket_via in ('web', 'email', 'chat') then t.ticket_via
        else 'other'
    end as channel,
    g.name as group_name,
    t.priority,
    t.recipient,
    t.tags,
    t.status,
    coalesce(cast(t.is_public as boolean), false) as has_public_comments,
    cast(c.custom_fields as json) as custom_fields,
    cast(json_extract(t.satisfaction_rating,'$.score') as varchar) as score,
    cast(json_extract(t.satisfaction_rating,'$.reason') as varchar) as reason,
    cast(json_extract(t.satisfaction_rating,'$.comment') as varchar) as comment,
    json_extract_scalar(cast(c.custom_fields as json), '$["Tipo de Solicitação"]')  as request_type,
    json_extract_scalar(cast(c.custom_fields as json), '$["Tipo de Cliente"]') as client_type,
    cast(t.ts_created as timestamp with time zone) as ts_created,
    cast(t.ts_created_local as timestamp with time zone) as ts_created_local,
    cast(t.ts_updated as timestamp with time zone) as ts_updated,
    -- bug caused by start delay of daylight saving time
    if(cast(t.ts_updated as timestamp with time zone) >= cast('2018-10-23 02:00:00 UTC' as timestamp with time zone) and
	cast(t.ts_updated as timestamp with time zone) <= cast('2018-11-04 03:00:00 UTC' as timestamp with time zone),
		cast(t.ts_updated as timestamp with time zone) at time zone 'GMT-3',
		cast(t.ts_updated as timestamp with time zone) at time zone 'Brazil/East') as ts_updated_local,
    now() as ts_load
from last_updated_ticket te
inner join tickets_filter t
on te.id_ticket = t.id_ticket and te.ts_updated = t.ts_updated
left join groups g
on t.id_group = g.id_group
left join datalake_clean.zendesk_custom_fields c
on t.id_ticket = c.id_ticket
