select distinct
	liq.sk_contract_signed_date,
	liq.sk_property,
	agent.nome as agent_name,
	sig."date" as dt_contract_signed,
	c.contract_status,
	case
		when substring(p.id for 4) = '8927' then substring(p.id from 5)
		when substring(p.id for 4) = '8928' then concat('1',substring(p.id from 5))
	end as short_id_property,
	r.name as property_region,
	(dense_rank() over (partition by liq.sk_contract order by liq.sk_user_agent asc) +
	dense_rank() over (partition by liq.sk_contract order by liq.sk_user_agent desc) - 1) as number_of_agents_contract,
	c.renting_value,
	visitor.nome as name_visitor,
	case
		when sig."date" < '2018-02-12' then 0.2
		else coalesce(ranking.commission,0.2)
	end as contract_commission,
	p.endereco
from
	public.fact_liquidity_property_scheduling liq
left join
	public.dim_contract c
	on liq.sk_contract = c.sk_contract
left join
	public.dim_date sig
	on liq.sk_contract_signed_date = sig.sk_date
left join
	public.dim_user visitor
	on liq.sk_user_visitor =  visitor.sk_user
left join
	public.dim_user agent
	on liq.sk_user_agent =  agent.sk_user
left join
	public.dim_property p
	on liq.sk_property = p.sk_property
left join
	public.dim_region r
	on r.sk_region = p.regiao_id
left join
	public.dim_booking b
	on liq.sk_booking = b.sk_booking
left join
	growth.agents_performance_ranking ranking
	on ranking.agent_id = agent.sk_user
	and extract(week from dt_ranking) = extract(week from current_date)-1
	and extract(year from sig."date") = extract(year from (current_date - interval '1 week')::date)
where sig."date" is not null
and visit_follow_up in ('NaoGostou', 'Talvez', 'VaiNegociar', 'VisitouSozinho')
