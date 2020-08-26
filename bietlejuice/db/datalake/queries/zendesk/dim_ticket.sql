with tickets_filter as (
	select distinct t.*
	from datalake_clean.zendesk_tickets t
	where (t.ticket_via<>'api' or (t.ticket_via='api' and t.tags not like '%hsm%'))
		and t.dt_extracted='{extraction_date}'
),
last_updated_ticket as (
	select id_ticket, max(ts_updated) as ts_last_updated from tickets_filter group by 1
),
distinct_groups as (
	with last_updated_group as (
		select
			id_group,
			max(ts_updated) as ts_last_updated
		from datalake_clean.zendesk_groups
		group by 1
	)
	select
		g.id_group,
		g.name,
		g.url_group
	from datalake_clean.zendesk_groups g
	inner join last_updated_group ge
		on ge.id_group = g.id_group and ge.ts_last_updated = g.ts_updated
	group by 1,2,3
),
distinct_ticket_fields as (
	with last_updated_ticket_field as (
		select
			id_ticket_fields,
			max(ts_updated) as ts_last_updated
		from datalake_clean.zendesk_ticket_fields
		group by 1
	)
	select
		cf.id_ticket_fields,
		cf.raw_title
	from datalake_clean.zendesk_ticket_fields cf
	inner join last_updated_ticket_field ltf
		on cf.id_ticket_fields=ltf.id_ticket_fields and cf.ts_updated=ltf.ts_last_updated
	group by 1,2
),
custom_fields_filter as (
	select
		id_ticket,
		custom_fields
	from datalake_clean.zendesk_custom_fields
	where dt_extracted='{extraction_date}'
),
parse_fields as (
  select c.id_ticket,
		replace(replace(regexp_extract(cf.field, '([^:]+)'), '"', ''), '"', '') as id_field,
		replace(regexp_extract(cf.field, '[^:]*$'), '"', '') as value
	from custom_fields_filter c
	CROSS JOIN UNNEST(SPLIT(c.custom_fields,',')) AS cf (field)
),
transformed_custom_fields as (
	select
		f.id_ticket,
		cast(map_agg(tf.raw_title, f.value) as json) as custom_fields
	from parse_fields f
	inner join distinct_ticket_fields tf
		on f.id_field = tf.id_ticket_fields
	group by 1
),
custom_field_ids as (
	select
		c.id_ticket,
		c.custom_fields,
		cast(json_extract(c.custom_fields,'$["Tipo de Solicitação"]') as varchar) as request_type,
		replace(cast(json_extract(c.custom_fields,'$["Tipo de Cliente"]') as varchar), '}}', '') as client_type,
		nullif(regexp_extract(cast(json_extract(custom_fields,'$["Cliente Tag"]') as varchar),'^[a-zA-Z_]*'),'') as customer_type_tag,
		nullif(regexp_extract(cast(json_extract(custom_fields,'$["Motivo Tag"]') as varchar),'^[a-zA-Z_]*'),'') as contact_motivation_tag,
		cast(json_extract_scalar(custom_fields,'$["Assunto Tag"]') as varchar) as contact_theme_tag
	from transformed_custom_fields c
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
	cfi.custom_fields,
	cast(json_extract(t.satisfaction_rating,'$.score') as varchar) as score,
	cast(json_extract(t.satisfaction_rating,'$.reason') as varchar) as reason,
	cast(json_extract(t.satisfaction_rating,'$.comment') as varchar) as comment,
	cfi.request_type,
	cfi.client_type,
	cfi.customer_type_tag,
	cfi.contact_motivation_tag,
	cfi.contact_theme_tag,
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
on te.id_ticket = t.id_ticket and te.ts_last_updated = t.ts_updated
left join distinct_groups g
on t.id_group = g.id_group
left join custom_field_ids cfi
on t.id_ticket = cfi.id_ticket
