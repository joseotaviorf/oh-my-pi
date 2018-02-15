create table growth_staging.post_contract_ticket_base as
with grouped_tasks as (
	select
		start_date::date as dt,
		assignee_id,
		workgroup_title,
		count(1) as _count
	from
		crm.tasks
	where
		start_date >= '2018-01-01'::date
	group by
		start_date::date,
		assignee_id,
		workgroup_title
),
aggreg as (
	select
		g.dt,
		g.assignee_id,
		g.workgroup_title,
		g._count,
		lw.workgroup_title as last_workgroup,
		sum(lw._count) as _sum
	from
		grouped_tasks g
	left join
		grouped_tasks lw
		on g.assignee_id = lw.assignee_id
		and lw.dt >= (g.dt - interval '1 week')::date
		and lw.dt < g.dt
		and lw.workgroup_title <> ''
	where g.workgroup_title = ''
	group by
		g.dt,
		g.assignee_id,
		g.workgroup_title,
		g._count,
		lw.workgroup_title
),
new_workgroup as (
	select
		dt,
		assignee_id,
		last_workgroup,
		first_value(last_workgroup)
			over(partition by assignee_id, dt
			order by _sum desc
			rows between unbounded preceding and unbounded following) as probable_wg
	from
		aggreg
),
to_from as (
	select
		dt,
		assignee_id,
		probable_wg
	from
		new_workgroup
	where last_workgroup = probable_wg
),
filtered as (
	select
		t.start_date::date as dt_created,
		t.workgroup_title,
		case
			when workgroup_title = '' then coalesce(probable_wg, '')
			else workgroup_title
		end as workgroup
	from
		crm.tasks t
	left join
		to_from tf
		on tf.dt = t.start_date::date
		and tf.assignee_id = t.assignee_id
	where t.workgroup_title in
	(
		'Apólices',
		'Chaves',
		'Collections',
		'Confirmar dados',
		'Confirmar fornecedoras',
		'E-mails onboarding',
		'Laudo Vistoria',
		'Mediação pós contrato',
		'Motoboy',
		'Offboarding',
		'Onboarding Rental',
		'Payments',
		'Titularidade',
		'Verificar Contas',
		'Vistoria',
		''
	)
)
select
	dt_created,
	sum(_count) as _count
from
(
	select
		dt_created,
		count(1) as _count
	from
		filtered
	where
		workgroup <> '' and dt_created > '2016-01-01'::date
	group by
		dt_created

	union all

	select
		dt_created,
		_count
	from
		growth_staging.post_contract_tickets_and_whatsapp

	union all

	select
		date(chat_start_timestamp) as dt_created,
		count(distinct(zendesk_ticket_id)) as _count
	from
		zendesk.chats
	where
		department_name = 'Já estou alugando com o QuintoAndar'
	group by
		date(chat_start_timestamp)

	union all

	select
		date(call_start) as dt_created,
		count(distinct(id)) as _count
	from
		public.asterisk_calls
	where
		queue_enter is not null
		and queue_name like 'ADM%'
	group by
		date(call_start)
)
group by dt_created
;
