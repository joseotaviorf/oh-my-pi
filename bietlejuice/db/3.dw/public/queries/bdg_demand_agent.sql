WITH demand AS (
SELECT
	d.ods_id AS sk_demand,
	d.sk_visit_date AS dt,
	U.dados_agente_id AS sk_agent
FROM
public.fact_demand d
JOIN public.dim_user u
	ON d.sk_user_agent = u.id
),
agent AS (
SELECT
	a.sk_slot_date AS dt,
	a.sk_agent AS sk_agent,
	a.sk_slot_date_agent AS sk_slot_date_agent
FROM
public.fact_agent a
)
SELECT
	COALESCE(demand.sk_demand, -1) AS sk_demand,
	COALESCE(COALESCE(demand.dt, agent.dt), -1) AS dt,
	COALESCE(COALESCE(demand.sk_agent, agent.sk_agent), -1) AS sk_agent,
	COALESCE(agent.sk_slot_date_agent, -1) AS sk_slot_date_agent
FROM demand
FULL OUTER JOIN
agent
ON  demand.dt = agent.dt
    AND demand.sk_agent = agent.sk_agent