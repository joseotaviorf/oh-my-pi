WITH listing_rent_flow AS (
    SELECT
        l.ods_id AS sk_listing_rent_flow,
        U.dados_agente_id AS sk_agent,
        l.sk_visit_date AS sk_date
    FROM
        dw_rent.fact_listing_rent_flows l
    JOIN
        dw_public.dim_user u
            ON l.sk_user_agent = u.id
),
agent AS (
    SELECT
        a.sk_agent,
        a.sk_slot_date_agent,
        a.sk_slot_date AS sk_date
    FROM
        dw_agent.fact_agent_daily_allocations a
)
SELECT
    CAST(COALESCE(lrf.sk_listing_rent_flow, -1) AS BIGINT) AS sk_listing_rent_flow,
    CAST(COALESCE(lrf.sk_date, agent.sk_date, -1) AS INT) AS sk_date,
    CAST(COALESCE(lrf.sk_agent, agent.sk_agent, -1) AS INT) AS sk_agent,
    CAST(COALESCE(agent.sk_slot_date_agent, -1) AS BIGINT) AS sk_slot_date_agent,
    NOW() as ts_load
FROM
    listing_rent_flow lrf
FULL OUTER JOIN
    agent
    ON  lrf.sk_date = agent.sk_date
        AND lrf.sk_agent = agent.sk_agent
