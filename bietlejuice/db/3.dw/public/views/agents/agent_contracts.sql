drop view if exists vw_agent_contracts;
create or replace view vw_agent_contracts as
select distinct
	f.sk_contract_signed_date,
  f.sk_house,
  f.sk_contract,
  agent.nome as agent_name,
  dprop.nome as owner_name,
  dprop.cpf as owner_cpf,
  sig."date" as dt_contract_signed,
	c.contract_status,
  case
  	when substring(p.id for 4) = '8927'
  		then substring(p.id from 5)
		when substring(p.id for 4) = '8928'
			then concat('1',substring(p.id from 5))
	end as short_id_property,
	r.name as property_region,
	(
		dense_rank() over (partition by f.sk_contract order by f2.sk_user_agent asc)
			+ dense_rank() over (partition by f.sk_contract order by f2.sk_user_agent desc)
			- 1
	) as number_of_agents_contract,
	c.renting_value,
	visitor.nome as name_visitor,
	case
		when sig."date" < '2018-02-12'
			then 0.2
		else coalesce(ranking.commission,0.2)
	end as contract_commission,
	p.endereco
from fact_demand f
left join fact_demand f2
	on f2.sk_house = f.sk_house
		and f2.sk_client = f.sk_client
left join dim_contract c
	on f.sk_contract = c.sk_contract
left join dim_date sig
	on f.sk_contract_signed_date = sig.sk_date
left join dim_user visitor
	on f.sk_client = visitor.sk_user
left join dim_user agent
	on f2.sk_user_agent = agent.sk_user
left join dim_property p
	on f2.sk_house = p.sk_property
left join dim_user dprop
	on dprop.sk_user = f.sk_owner
left join dim_region r
	on r.sk_region = p.regiao_id
left join dim_booking b
	on f2.sk_booking = b.sk_booking
left join growth.agents_performance_ranking ranking
	on ranking.agent_id = agent.sk_user
		and extract(week from dt_ranking) = extract(week from sig."date")
		and extract(year from dt_ranking) = extract(year from sig."date")
where sig."date" is not null
	and visit_follow_up in ('NaoGostou', 'Talvez', 'VaiNegociar', 'VisitouSozinho')
;