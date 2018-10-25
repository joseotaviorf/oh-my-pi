select distinct
	f.sk_contract_signed_date,
  f.sk_house_listing,
  f.sk_contract,
  agent.nome as agent_name,
  coalesce(ecp.nome, nullif(dprop.nome, '')) as owner_name,
  coalesce(ecp.cpf, nullif(dprop.cpf, '')) as owner_cpf,
  sig."date" as dt_contract_signed,
	c.contract_status,
  p.short_id as short_id_property,
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
		else coalesce(ranking.commission, 0.2)
	end as contract_commission,
	p.endereco
from public.fact_demand f
left join public.fact_demand f2
	on f2.sk_house_listing = f.sk_house
		and f2.sk_client = f.sk_client
left join public.dim_contract c
	on f.sk_contract = c.sk_contract
left join public.dim_date sig
	on f.sk_contract_signed_date = sig.sk_date
left join public.dim_user visitor
	on f.sk_client = visitor.sk_user
left join public.dim_user agent
	on f2.sk_user_agent = agent.sk_user
left join public.dim_house_listing p
	on f2.sk_house_listing = p.sk_house_listing
left join public.dim_user dprop
	on dprop.sk_user = f.sk_owner
left join datalake_raw.ebdb_contratopessoa ecp
	on ecp.contrato_id::bigint = f.sk_contract
		and ecp.tipo = 'Proprietario'
left join public.dim_region r
	on r.sk_region = p.regiao_id
left join public.dim_booking b
	on f2.sk_booking = b.sk_booking
left join growth.agents_performance_ranking ranking
	on ranking.agent_id = agent.sk_user
		and ranking.sk_date = to_char(date(sig.week_start),'YYYYMMDD')
where sig."date" is not null
	and b.visit_follow_up in ('VaiNegociar', 'NaoGostou', 'VisitouSozinho', 'Talvez')
;