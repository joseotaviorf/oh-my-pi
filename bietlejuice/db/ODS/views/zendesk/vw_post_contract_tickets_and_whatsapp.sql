drop view if exists zendesk.vw_post_contract_tickets_and_whatsapp;
create view zendesk.vw_post_contract_tickets_and_whatsapp as
with whatsapp as (
	select
		t.created_at::date as dt_created,
		count(t.id) as _count
	from
		zendesk.ticket t
	left join
		zendesk."group" g
		on t.group_id = g.id
	left join
		(select * from zendesk.tag where value = 'zapdesk_disparo5a') auto
		on auto.object_id = t.id
	left join
		(select * from zendesk.tag where value = 'cliente') cli
		on cli.object_id = t.id
	where t.is_whatsapp = true
		and auto.object_id is null
		and cli.object_id is not null
	group by t.created_at::date
),
tickets as (
	select
		t.created_at::date as dt_created,
		count(1) as _count
	from
		zendesk.ticket t
	left join
		zendesk."group" g
		on t.group_id = g.id
	left join
		zendesk.via v
		on t.via_id = v.id
	where g."name" in
	(
		'ADM Casos',
		'ADM Mediações',
		'ADM Offboarding',
		'ADM Onboarding',
		'ADM Renovação',
		'ADM Rescisão',
		'CX Administração',
		'CX Pós',
		'Casos Especiais',
		'Collections',
		'Crise',
		'Payments Tasks',
		'Vistoria'
	)
	and is_whatsapp = false
	and v.channel <> 'chat'
	group by
		t.created_at::date
)
select
	coalesce(t.dt_created, w.dt_created)::date as dt_created,
	coalesce(t._count,0) + coalesce(w._count,0) as _count
from
	tickets t
full outer join
	whatsapp w
	on t.dt_created = w.dt_created
;