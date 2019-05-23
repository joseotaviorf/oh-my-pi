with tickets_filter as (
	select distinct t.* 
    from datalake_clean.zendesk_tickets t
	where (t.channel<>'api' or (t.channel='api' and t.tags not like '%hsm%'))
	and t.dt_extracted='{partition_date}'
),
last_ticket_entries as (
    select id_ticket, max(ts_updated) as ts_updated from tickets_filter group by 1
),
last_group_entries as (
    select id_group, max(ts_updated) as ts_updated from datalake_clean.zendesk_groups group by 1
),
groups as (
    select
        g.id_group,
        g.name,
        g.url_group
    from datalake_clean.zendesk_groups g
    inner join last_group_entries ge
    on ge.id_group = g.id_group and ge.ts_updated = g.ts_updated
    group by 1,2,3
),
parse_fields as (
    select tf.id_ticket,
        f1.field,
        regexp_extract(f1.field, '{\\?"id\\?":"?(\d+)"?', 1) as field_id,
        nullif(regexp_extract(f1.field, '"value\\?":\\?"?([^\\?"|}]+)', 1), 'null') as value
    from tickets_filter tf
    inner join last_ticket_entries te 
    on te.id_ticket = tf.id_ticket and te.ts_updated = tf.ts_updated
    cross join unnest(regexp_extract_all(tf.custom_fields, '{[^}]+[^,]+[^{]+}')) as f1(field)
),
fields_map as (
    select p.id_ticket,
        map_agg(tf.raw_title, p.value) as cols
    from parse_fields p
    left join datalake_clean.zendesk_ticket_fields tf
       on tf.id_ticket_fields = p.field_id
    where p.value is not null
    group by p.id_ticket
)
select
    t.id_ticket,
    t.subject,
    t.description,
    t.channel,
    g.name as groups,
    t.priority,
    t.recipient,
    t.tags,
    t.status,
    cast(t.is_public as boolean) as is_public_comments,
	json_format(cast(map.cols as JSON)) as custom_fields,
    cast(json_extract(t.satisfaction_rating,'$.score') as varchar) as score,
    cast(json_extract(t.satisfaction_rating,'$.reason') as varchar) as reason,
    cast(json_extract(t.satisfaction_rating,'$.comment') as varchar) as comment,
    map.cols['Tipo de Solicitação'] as request_type,
    map.cols['Tipo de Cliente'] as client_type,
    cast(t.ts_created as timestamp) as ts_created,
    cast(t.ts_created_local as timestamp) as ts_created_local
from last_ticket_entries te
inner join tickets_filter t
on te.id_ticket = t.id_ticket and te.ts_updated = t.ts_updated
left join groups g
on t.id_group = g.id_group
left join fields_map map
on t.id_ticket = map.id_ticket;
