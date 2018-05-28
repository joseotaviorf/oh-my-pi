create view vw_agent_contracts as (
select distinct
    liq.sk_contract_signed_date,
    liq.sk_house,
    liq.sk_contract,
    agent.nome   as agent_name,
    sig."date" as dt_contract_signed,
    c.contract_status,
    case when substring(p.id FOR 4) = '8927' THEN
    substring(p.id FROM 5)
WHEN substring(p.id FOR 4) = '8928' THEN
 concat('1',substring(p.id FROM 5))
END
AS short_id_property,r.NAME AS property_region,(dense_rank() OVER (partition BY liq.sk_contract ORDER BY liq2.sk_user_agent ASC) +dense_rank() OVER (partition BY liq.sk_contract ORDER BY liq2.sk_user_agent DESC) - 1) AS number_of_agents_contract, c.renting_value, visitor.nome AS name_visitor, case
WHEN sig."date" < '2018-02-12' THEN
 0.2
 ELSE COALESCE(ranking.commission,0.2)
END
AS contract_commission, p.endereco from PUBLIC.fact_demand liq LEFT join PUBLIC.fact_demand liq2 ON liq2.sk_house = liq.sk_house
AND
liq2.sk_client = liq.sk_client LEFT join PUBLIC.dim_contract c ON liq.sk_contract = c.sk_contract LEFT join PUBLIC.dim_date sig ON liq.sk_contract_signed_date = sig.sk_date LEFT join PUBLIC.dim_user visitor ON liq.sk_client = visitor.sk_user LEFT join PUBLIC.dim_user agent ON liq2.sk_user_agent = agent.sk_user LEFT join PUBLIC.dim_property p ON liq2.sk_house = p.sk_property LEFT join PUBLIC.dim_region r ON r.sk_region = p.regiao_id LEFT join PUBLIC.dim_booking b ON liq2.sk_booking = b.sk_booking LEFT join growth.agents_performance_ranking ranking ON ranking.agent_id = agent.sk_user
AND
extract(week FROM dt_ranking) = extract(week FROM sig."date")
AND
extract(year FROM dt_ranking) = extract(year FROM sig."date") where sig."date" IS NOT null
AND
visit_follow_up IN ('NaoGostou',
                   'Talvez',
                   'VaiNegociar',
                   'VisitouSozinho'))
                   select extract(year from dp.publication_date) as _year,
                   extract(month from dp.publication_date) as _month,
                   count(distinct dp.sk_property) as dist,
                   count(dp.sk_property) as rep
                   from dim_property dp
                   join dim_region dr
                   	on dp.regiao_id = dr.sk_region
                   where dp.start_version_category in ('First Listing', 'Recovered')
                   	and dr.city_name = 'São Paulo'
                   	and dp.publication_date >= '2017-01-01'
                   	group by 1, 2
                   	order by 1, 2
                   	;