with demand as (
select
	d.ods_id as sk_demand,
	d.sk_visit_date as dt,
	U.dados_agente_id as sk_agent
from
public.fact_demand d
JOIN public.dim_user u
	ON d.sk_user_agent = u.id
),
agent as (
select
	a.sk_slot_date as dt,
	a.sk_agent as sk_agent,
	a.sk_slot_date_agent as sk_slot_date_agent
FROM
public.fact_agent a
)
SELECT
	coalesce (demand.sk_demand, -1) as sk_demand,
	COALESCE(COALESCE(demand.dt, agent.dt), -1) as dt,
	COALESCE(COALESCE(demand.sk_agent, agent.sk_agent), -1) as sk_agent,
	COALESCE(agent.sk_slot_date_agent, -1) as sk_slot_date_agent
FROM demand
FULL OUTER JOIN
	agent
	ON demand.dt = agent.dt
		AND demand.sk_agent = agent.sk_agent