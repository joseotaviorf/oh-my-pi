WITH listing_rent_flow AS (
SELECT
	l.ods_id AS sk_demand,
	l.sk_visit_date AS dt,
	U.dados_agente_id AS sk_agent
FROM
public.fact_listing_rent_flows l
JOIN public.dim_user u
	ON l.sk_user_agent = u.id
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
	COALESCE(lrf.sk_demand, -1) AS sk_demand,
	COALESCE(lrf.dt, agent.dt, -1) AS dt,
	COALESCE(lrf.sk_agent, agent.sk_agent, -1) AS sk_agent,
	COALESCE(agent.sk_slot_date_agent, -1) AS sk_slot_date_agent,
	getdate() as dt_timestamp
FROM listing_rent_flow lrf
FULL OUTER JOIN
agent
ON  lrf.dt = agent.dt
    AND lrf.sk_agent = agent.sk_agent