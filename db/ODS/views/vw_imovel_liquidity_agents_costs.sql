drop view if exists vw_imovel_liquidity_agents_costs;
create view vw_imovel_liquidity_agents_costs as
select
    date_part('year', p."contract_created_date") as contract_year,
	date_part('month', p."contract_created_date") as contract_month,
    p.email,
    i.email as email_agent,
    p.id_scheduling,
    p.id_imovel,
    i.id_imovel as id_imovel_agent,
    p.id_negotiation,
    p.id_visit,
    p.id_proposal,
    p.id_pre_proposal,
    p.id_contract,
    p.id_user_agent,
    coalesce(nullif(count(1) over (partition by i.id_imovel) ,0),1) as qt_lines_per_contract,
	i.value as total_cost_agents_comission,
    i.value
      / coalesce(nullif(count(1) over (partition by i.id_imovel) ,0),1) as cost_agents_comission

from
  (
    select
      email,
      892700000 + "Imovel"::integer as id_imovel,
      "Assinatura" as dt_assinatura,
      "Amount earned"::decimal(14,4) as value
    from
      files.agent_comission_over_contract_closed
  ) i
left join
(
  select
    p.id_scheduling,
    p.id_imovel,
    p.id_negotiation,
    p.id_visit,
    p.id_proposal,
    p.id_pre_proposal,
    p.id_contract,
    p.id_user_agent,
	u.id as usuario_id,
    u.email,
    c."criadoEm" as contract_created_date
  from
      property_scheduling p
  inner join
      usuario u
      on u.id = p.id_user_agent
  inner join
      contract c
      on c.id = p.id_contract
      and c.status != 'Cancelado'
) p
  on  p.id_imovel = i.id_imovel
  and p.email = i.email
--  and date_part('year', c."criadoEm") = date_part('year', i.dt_assinatura)
--  and date_part('month', c."criadoEm") = date_part('month', i.dt_assinatura)


-- where
-- 	id_imovel in (892793409, 892792498) -- 892794821 --  892795561 --892795561 -- 892796019 -- 892795502
order by
	1 desc,
    2 desc
;


--select * from vw_imovel_liquidity_agents_costs where id_imovel = 892774268

/*
select
	email,
    8927 + "Imovel" as id_imovel,
    "Assinatura" as dt_assinatura,
	"Amount earned"::decimal(14,4) as value
from
	files.agent_comission_over_contract_closed
-- select * from contract where imovel_id = 892783195
-- select status, * from imovel where id = 892783195
select * from vw_imovel_liquidity_agents_costs where
id_imovel = 892795246
*/