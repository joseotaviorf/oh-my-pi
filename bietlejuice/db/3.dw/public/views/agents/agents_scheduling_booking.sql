drop view if exists vw_agents_scheduling_booking;
create or replace view vw_agents_scheduling_booking as (
select
	ags.agent_id,
	du.dados_agente_id,
	ags.agent_name,
    cast(ags.available_slots_96 as INTEGER) as available_slots,
	cast(ags.available_slots_0 as INTEGER) as available_slots_0,
	ags.slot_dt::date,
	count(db.sk_booking) as visits_completed
from staging.agents_scheduling ags
join dim_user du
	on du.id = ags.agent_id
left join dim_booking db
	on db.id_agent = du.dados_agente_id
		and db.dt_scheduling::date = ags.slot_dt::date
		and db."type" = 'Visita'
		and db.visit_follow_up in ('Talvez', 'VisitouSozinho', 'VaiNegociar', 'NaoGostou')
group by 1, 2, 3, 4, 5, 6
)
;