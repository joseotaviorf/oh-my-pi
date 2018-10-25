DROP VIEW vw_agent_contracts;

CREATE VIEW vw_agent_contracts AS
(
    SELECT DISTINCT liq.sk_contract_signed_date,
                    liq.sk_house_listing,
                    liq.sk_contract,
                    agent.nome AS agent_name,
                    sig."date" AS dt_contract_signed,
                    c.contract_status,
                    CASE WHEN substring(p.id for 4) = '8927' THEN substring(p.id FROM 5)
                         WHEN substring(p.id FOR 4) = '8928' THEN concat('1',substring(p.id FROM 5))
                    END AS short_id_property,
                    r.NAME AS property_region,
                    (dense_rank() OVER (partition BY liq.sk_contract ORDER BY liq2.sk_user_agent ASC) +dense_rank() OVER (partition BY liq.sk_contract ORDER BY liq2.sk_user_agent DESC) - 1) AS number_of_agents_contract,
                    c.renting_value,
                    visitor.nome AS name_visitor,
                    CASE WHEN sig."date" < '2018-02-12' THEN 0.2
                         ELSE COALESCE(ranking.commission,0.2)
                    END AS contract_commission,
                    p.endereco
    FROM
        PUBLIC.fact_demand liq
    LEFT JOIN
        PUBLIC.fact_demand liq2
        ON liq2.sk_house_listing = liq.sk_house
        AND liq2.sk_client = liq.sk_client
    LEFT JOIN
        PUBLIC.dim_contract c
        ON liq.sk_contract = c.sk_contract
    LEFT JOIN
        PUBLIC.dim_date sig
        ON liq.sk_contract_signed_date = sig.sk_date
    LEFT JOIN
        PUBLIC.dim_user visitor
        ON liq.sk_client = visitor.sk_user
    LEFT JOIN
        PUBLIC.dim_user agent
        ON liq2.sk_user_agent = agent.sk_user
    LEFT JOIN
        PUBLIC.dim_house_listing p
        ON liq2.sk_house_listing = p.sk_house_listing
    LEFT JOIN
        PUBLIC.dim_region r
        ON r.sk_region = p.regiao_id
    LEFT JOIN
        PUBLIC.dim_booking b
        ON liq2.sk_booking = b.sk_booking
    LEFT JOIN
        growth.agents_performance_ranking ranking
        ON ranking.agent_id = agent.sk_user
        AND extract(week FROM dt_ranking) = extract(week FROM sig."date")
        AND extract(year FROM dt_ranking) = extract(year FROM sig."date")
    WHERE sig."date" IS NOT NULL
        AND visit_follow_up IN ('NaoGostou',
                                'Talvez',
                                'VaiNegociar',
                                'VisitouSozinho')
)