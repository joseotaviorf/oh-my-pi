drop view if exists vw_imovel_liquidity_closing_costs;
create view vw_imovel_liquidity_closing_costs as
-- closing support
-- ratear custo do mes, por dia pelos imoveis que tiveram contrato
select
    p.id_property_scheduling,
	c."criadoEm"::date as contract_date,
    p.id_scheduling,
    p.id_imovel,
    p.id_negotiation,
    p.id_visit,
    p.id_proposal,
    p.id_pre_proposal,
    p.id_contract,
    p.id_user_agent,
    c.status,
    i.value as total_closing_support_cost,
    c_d.days_in_month,

    coalesce(nullif
      ( -- equivalent a count(distinct id_imovel) over (...)
      	-- because count(distinct) wasn`t implemented in window functions
      	dense_rank() over (
          partition by
            c."criadoEm"::date
          order by p.id_imovel
        )
        + dense_rank() over (
            partition by
              c."criadoEm"::date
            order by p.id_imovel desc)
        - 1
        ,0
      ),1) as qt_properties_month,
    coalesce(nullif(count(1) over (partition by c.id) ,0),1) as qt_lines_per_contract_month,
    -i.value /
      coalesce(c_d.days_in_month,1) /
      coalesce(nullif
      ( dense_rank() over (
           partition by
            c."criadoEm"::date
          order by p.id_imovel
        )
        + dense_rank() over (
           partition by
            c."criadoEm"::date
            order by p.id_imovel desc)
        - 1
        ,0
      ),1) /
      coalesce(nullif(count(p.id_contract) over (partition by c."criadoEm") ,0),1)
    as cost_closing_support
from
  property_scheduling p
inner join
  contract c
  on c.id = p.id_contract
 -- and c.status !=  'Cancelado'
inner join
(
  select
    date_part('year', c."criadoEm") as year,
    date_part('month', c."criadoEm") as month,
    count(distinct c."criadoEm"::date)  as days_in_month
  from
    contract c
  group by
    date_part('year', c."criadoEm"),
    date_part('month', c."criadoEm")
) c_d
  on c_d.year = date_part('year', c."criadoEm")
  and c_d.month = date_part('month', c."criadoEm")
left join
  (
    select
      date_part('year', i."Month") as year,
      date_part('month', i."Month") as month,
      sum(i."Value") as value
    from
      files.costs_dre i
    where
      i."Category" = 'Closing Expenses'
    group by
      i."Month"
  ) i
  on date_part('year', c."criadoEm") = i.year
  and date_part('month', c."criadoEm") = i.month
;
-- where imovel_id =  892786796
-- select * from booking where imovel_id =  892786796
/*
select distinct status from contract
select
	*
from
	vw_imovel_liquidity_closing_costs
where
	date_part('year', contract_date) = 2016
    and 	date_part('month', contract_date)= 10
select * from vw_imovel_liquidity_closing_costs  where id_imovel =  892786796
select
  count(distinct b.id)
from
  property_scheduling p
inner join
  booking b
  on b.id = p.id_scheduling
  and b."fupVisita" is not null -- and b.status != 'Cancelado'
where
	date_part('year', b."criadoEm") = 2016
  and date_part('month', b."criadoEm") = 10
*/
