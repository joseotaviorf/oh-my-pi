with tickets_filter as (
	select t.* from datalake_clean.zendesk_tickets t
	where t.channel != 'api'
	__WHERE_CLAUSE__
),
max_ticket_groups as (
	select
		id,
		max(dt_extraction) as dt_extraction
	from datalake_clean.zendesk_groups
	group by 1
),
last_ticket_groups as (
	select
		url,
		mg.id,
		name,
		deleted,
		created_at,
		updated_at,
		mg.dt_extraction
	from max_ticket_groups mg
	join datalake_clean.zendesk_groups g
	 on g.id = mg.id and g.dt_extraction = mg.dt_extraction
),
parse_fields as (
    select zt.id,
        f1.field,
        regexp_extract(f1.field, '.*{\\?"id\\?":(\d+)', 1) as field_id,
        nullif(regexp_extract(f1.field, '"value\\?":\\?"?([^\\?"|}]+)', 1), 'null') as value
    from tickets_filter zt
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
last_fields as (
	select
	  t.id,
	  t.subject,
	  t.description,
	  t.channel,
	  t.priority,
	  t.recipient,
	  t.tags,
	  t.satisfaction_rating,
	  date_parse(regexp_extract(t.description, 'Chat started: (\d+.\d+.\d+ \d+:\d+ \wM)', 1), '%Y-%m-%d %h:%i %p') as chat_started_at,
	  t.created_at,
	  t.group_id,
	  max(t.updated_at) as updated_at
   from tickets_filter t
   group by 1,2,3,4,5,6,7,8,9,10,11
)
select
   t.id as sk_ticket,
   t.subject,
   t.description,
   t.channel,
   zg.name as box,
   t.priority,
   t.recipient,
   t.tags,
   t.satisfaction_rating,
   c.cols['Tipo de Solicitação'] as request_type,
   c.cols['Tipo de Cliente'] as client_type,
   date_parse(regexp_extract(t.description, 'Chat started: (\d+.\d+.\d+ \d+:\d+ \wM)', 1), '%Y-%m-%d %h:%i %p') as chat_started_at,
   t.created_at,
   current_timestamp as ts_load,
   t.updated_at
from last_fields t
left join fields_map c
    on c.id = t.id
left join last_ticket_groups zg
    on zg.id = t.group_id