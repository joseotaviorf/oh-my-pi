drop view if exists vw_imovel_liquidity_visit_costs;
create view vw_imovel_liquidity_visit_costs as
-- visit support
-- ratear custo do mes, por dia pelos agendamentos
select
	b."criadoEm"::date as booking_date,
	p.id_imovel,
    p.id_scheduling,
    p.id_negotiation,
    p.id_visit,
    p.id_proposal,
    p.id_offer,
    p.id_pre_proposal,
    p.id_contract,
    p.id_user_agent,
    i.value as total_visit_support_cost,
    coalesce(f_get_days_in_month(b."criadoEm"),1) as days_in_month,

    coalesce(nullif
      ( -- equivalent a count(distinct id_imovel) over (...)
      	-- because count(distinct) wasn`t implemented in window functions
      	dense_rank() over (
          partition by
            b."criadoEm"::date
          order by p.id_scheduling
        )
        + dense_rank() over (
            partition by
              b."criadoEm"::date
            order by p.id_scheduling desc)
        - 1
        ,0
      ),1) as qt_bookings_month,

    coalesce(nullif(count(1) over (partition by b.id) ,0),1) as qt_lines_per_contract_month,

    -i.value /
      coalesce(f_get_days_in_month(b."criadoEm"),1) /
      coalesce(nullif
      ( dense_rank() over (
          partition by
            b."criadoEm"::date
          order by p.id_scheduling
        )
        + dense_rank() over (
            partition by
              -- date_part('year', b."criadoEm") ,
              -- date_part('month', b."criadoEm")
              b."criadoEm"::date
            order by p.id_scheduling desc)
        - 1
        ,0
      ),1) /
	  coalesce(nullif(count(1) over (partition by b.id) ,0),1)
	as cost_visit
from
  property_scheduling p

inner join
  booking b
  on b.id = p.id_scheduling
  and b."fupVisita" is not null -- and b.status != 'Cancelado'

left join
  (
    select -- *
      date_part('year', i."Month") as year,
      date_part('month', i."Month") as month,
      sum(i."Value") as value
    from
      -- income_statement i
      files.costs_dre i
    where
      i."Category" in ('Assisted Scheduling', 'Assisted Confirmation', 'Visit Support')
    group by
      i."Month"
  ) i
  on date_part('year', b."criadoEm") = i.year
  and date_part('month', b."criadoEm") = i.month
-- where imovel_id =  892786796
-- select * from booking where imovel_id =  892786796
;



/*
select
	*
from
	vw_imovel_liquidity_visit_costs
where
	date_part('year', booking_date) = 2016
    and 	date_part('month', booking_date)= 10

select * from vw_imovel_liquidity_visit_costs  where id_imovel =  892786796


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


-- select * from vw_imovel_liquidity_visit_costs where id_imovel = 892764794
-- select * from vw_fact_liquidity_property_scheduling where sk_property = 892764794


-- select * from booking where imovel_id = 892764794