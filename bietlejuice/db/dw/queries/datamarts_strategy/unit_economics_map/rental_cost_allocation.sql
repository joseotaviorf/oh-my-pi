with rental_monthly_tickets_tasks_city as (
  WITH tic_tas_no_city as (
  select
  	tt.month,
  	tt.task_ticket_group,
  	sum(case when tt.city_group is null then tt.total_tickets_tasks end) as no_city_tickets_tasks
  from datamarts_strategy.rental_monthly_tickets_tasks tt
  group by 1,2
  ),
  tic_tas_with_city as (
  select
  	tt.month,
  	tt.task_ticket_group,
  	sum(case when tt.city_group is not null then tt.total_tickets_tasks end) as with_city_tickets_tasks
  from datamarts_strategy.rental_monthly_tickets_tasks tt
  group by 1,2
  ),
  city_group_share as (
  select
  	tt.month,
  	tt.task_ticket_group,
  	tt.city_group,
  	sum(case when tt.city_group is not null then tt.total_tickets_tasks end)/sum(ttc.with_city_tickets_tasks)::float as city_share
  from datamarts_strategy.rental_monthly_tickets_tasks tt
  left join tic_tas_with_city ttc
    on ttc.month = tt.month and ttc.task_ticket_group = tt.task_ticket_group
  group by 1,2,3
  )
  select
  	tt.sk_house_listing,
    tt.month,
    tt.city_group,
    tt.task_ticket_group,
    sum(coalesce(tt.tickets*(1+cgs.city_share),0)) as tickets,
    sum(coalesce(tt.tasks*(1+cgs.city_share),0)) as tasks,
    sum(coalesce(tt.total_tickets_tasks*(1+cgs.city_share),0)) as total_tickets_tasks
  from datamarts_strategy.rental_monthly_tickets_tasks tt
  left join city_group_share cgs
    on cgs.month = tt.month and cgs.task_ticket_group = tt.task_ticket_group and cgs.city_group = tt.city_group
  where tt.city_group is not null
  group by 1,2,3,4
),
datamart_kpi as (
  select
    month_date as month,
    city_group,
    sum(coalesce(ongoing_rentals_monthly,0)) as ongoing_rentals,
    sum(coalesce(new_rentals_monthly,0)) as total_new_rentals,
    sum(coalesce(new_rentals_monthly,0) + coalesce(ended_rentals_monthly,0)) as total_new_ended
  from datamarts.datamart_kpi_monthly
  where month_date >= '2019-07-01'
  group by 1,2
  order by 1 desc, 2
),
rental_costs_city as (
  select
    date(month) as month_cost,
    city_group,
    rental_onboarding::float as onboarding_costs,
    rental_offboarding::float as offboarding_costs,
    rental_ongoing::float as ongoing_costs,
    rental_band_aids::float as repairs_costs,
    rental_bank_transaction_fees::float as bank_fees,
    rental_key_delivery::float as key_delivery_costs,
    rental_inspection::float + rental_inspections::float as inspection_team_partner_costs
  from datalake_raw.ue_costs_financial_city_group
  where date(month) >= '2019-07-01'
),
tickets_tasks_costs as (
select
  rtt.month,
  rtt.city_group,
  ceiling(sum(case when rtt.task_ticket_group = 'onboarding' then rtt.total_tickets_tasks end)) as onboarding_tasks_tickets,
  ceiling(sum(case when rtt.task_ticket_group = 'offboarding' then rtt.total_tickets_tasks end)) as offboarding_tasks_tickets,
  ceiling(sum(case when rtt.task_ticket_group in ('ongoing', 'payments', 'repairs', 'linhadireta', 'manual', 'other') then rtt.total_tickets_tasks end)) as ongoing_tasks_tickets,
  dk.ongoing_rentals,
  dk.total_new_rentals,
  dk.total_new_ended,
  rc.onboarding_costs as onboarding_costs,
  rc.offboarding_costs as offboarding_costs,
  rc.ongoing_costs + rc.repairs_costs as ongoing_costs,
  rc.bank_fees as bank_fees,
  rc.key_delivery_costs * 0.3 as key_delivery_costs, -- 70% pre-rental/30% pos-rental
  rc.inspection_team_partner_costs as inspection_costs
from rental_monthly_tickets_tasks_city rtt
left join rental_costs_city rc
  on rtt.month = rc.month_cost and rc.city_group = rtt.city_group
left join datamart_kpi dk
  on rtt.month = dk.month and dk.city_group = rtt.city_group
group by 1,2,6,7,8,9,10,11,12,13,14
order by 1 desc
),
tickets_tasks_costs_unit  as (
select
  month,
  city_group,
  onboarding_costs/onboarding_tasks_tickets as onboarding_costs_unit,
  offboarding_costs/offboarding_tasks_tickets as offboarding_costs_unit,
  ongoing_costs/ongoing_tasks_tickets as ongoing_costs_unit,
  (case when ongoing_rentals <> 0 then bank_fees/ongoing_rentals else 0 end) as bank_fees_costs_unit,
  (case when total_new_rentals <> 0 then key_delivery_costs/total_new_rentals else 0 end) as key_delivery_costs_unit,
  (case when total_new_ended <> 0 then inspection_costs/total_new_ended else 0 end) as inspection_costs_unit
from tickets_tasks_costs ttc
),
ongoing_rentals_listing as (
select
	  dd.month_start,
	  hl.sk_house_listing,
	  count(distinct dc.sk_contract) as ongoing_rentals_monthly
from dim_contract dc
join dim_date dd
  on dd.date between date(coalesce(dc.dt_start, dc.dt_entrance)) and (coalesce(dc.dt_annulment, current_date) - interval '1 day')
left join fact_house_listings hl
  on dc.sk_contract = hl.sk_contract
where dc.status in ('Ativo', 'Finalizado') -- consider only contracts that are active or were active at a given period
  and dd.date = dd.month_end -- only look last day of the month
  and date(coalesce(dc.dt_start, dc.dt_entrance)) < current_date -- we know we may have future dates for dt_start
  and (dc.dt_annulment < current_date OR dc.dt_annulment is null) -- we know we may have future dates for dt_annulment
  and type <> 'DealOnly'
  and dd.month_start >= '2019-07-01'
group by 1, 2
),
new_rentals_listing as (
select
	date(date_trunc('month',coalesce(dc.dt_start, dc.dt_entrance))) as rental_month_start,
	rf.sk_house_listing,
	count(distinct dc.sk_contract) as new_rentals_monthly
from dim_contract dc
left join fact_listing_rent_flows rf
  on dc.sk_contract = rf.sk_contract
where dc.status in ('Ativo', 'Finalizado') -- consider only contracts that are active or were active at a given period
  and date(coalesce(dc.dt_start, dc.dt_entrance)) < current_date -- we know we may have future dates for dt_start
  and date(coalesce(dc.dt_start, dc.dt_entrance)) >= '2019-07-01'
group by 1, 2
),
ended_rentals_listing as (
select
	date(date_trunc('month',dc.dt_annulment)) as month_date,
	rf.sk_house_listing,
	count(distinct dc.sk_contract) as ended_rentals_monthly
from dim_contract dc
left join fact_listing_rent_flows rf
  using(sk_contract)
where dc.status = 'Finalizado'
      and dc.dt_annulment < current_date
      and dc.dt_annulment >= '2019-07-01'
group by 1, 2
),
tickets_tasks_listing as (
select
  rtt.month,
  rtt.city_group,
  rtt.sk_house_listing,
  ceiling(sum(case when rtt.task_ticket_group = 'onboarding' then rtt.total_tickets_tasks end)) as onboarding_tt_listing,
  ceiling(sum(case when rtt.task_ticket_group = 'offboarding' then rtt.total_tickets_tasks end)) as offboarding_tt_listing,
  ceiling(sum(case when rtt.task_ticket_group in ('ongoing', 'payments', 'repairs', 'linhadireta', 'manual', 'other') then rtt.total_tickets_tasks end)) as ongoing_tt_listing
from rental_monthly_tickets_tasks_city rtt
left join tickets_tasks_costs_unit ttc
  on ttc.month = rtt.month and ttc.city_group = rtt.city_group
  group by 1,2,3
),
month_costs as (
select
  ttl.month,
  ttl.city_group,
  ttl.sk_house_listing,
  round(ttl.onboarding_tt_listing * unit.onboarding_costs_unit,2) as onboarding_cost_total,
  round(ttl.offboarding_tt_listing * unit.offboarding_costs_unit,2) as offboarding_cost_total,
  round(ttl.ongoing_tt_listing * unit.ongoing_costs_unit,2) as ongoing_cost_total,
  round(orl.ongoing_rentals_monthly * unit.bank_fees_costs_unit,2) as bank_fees_cost_total,
  round(nrl.new_rentals_monthly * unit.key_delivery_costs_unit,2) as key_delivery_cost_total,
  round(coalesce((nrl.new_rentals_monthly + erl.ended_rentals_monthly),nrl.new_rentals_monthly,erl.ended_rentals_monthly) * unit.inspection_costs_unit,2) as inspection_cost_total
from tickets_tasks_listing ttl
left join tickets_tasks_costs_unit unit
  on unit.month = ttl.month and unit.city_group = ttl.city_group
left join ongoing_rentals_listing orl
  on orl.month_start = ttl.month and orl.sk_house_listing = ttl.sk_house_listing
left join new_rentals_listing nrl
  on nrl.rental_month_start = ttl.month and nrl.sk_house_listing = ttl.sk_house_listing
left join ended_rentals_listing erl
  on erl.month_date = ttl.month and erl.sk_house_listing = ttl.sk_house_listing
where ttl.month >= '2019-07-01'
)
select
  mc.city_group,
  mc.sk_house_listing,
  mc.onboarding_cost_total,
  mc.offboarding_cost_total,
  mc.ongoing_cost_total,
  mc.bank_fees_cost_total,
  mc.key_delivery_cost_total,
  mc.inspection_cost_total,
  sum(coalesce(mc.onboarding_cost_total,0) +
    coalesce(mc.offboarding_cost_total,0) +
    coalesce(mc.ongoing_cost_total,0) +
    coalesce(mc.bank_fees_cost_total,0) +
    coalesce(mc.key_delivery_cost_total,0) +
    coalesce(mc.inspection_cost_total,0)) as cost_total
from month_costs mc
group by 1,2,3,4,5,6,7,8;