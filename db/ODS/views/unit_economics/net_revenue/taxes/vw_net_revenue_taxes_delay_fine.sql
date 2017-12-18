drop view if exists unit_economics.vw_net_revenue_taxes_delay_fine;
create or replace view unit_economics.vw_net_revenue_taxes_delay_fine as
with filtered_dates as (
	select distinct
		date_trunc('month', dd."date") as dt
	from
		dim_date dd
),
filtered_fines as (
	select
		contract_id,
		sum(fine) as fine,
		paid_date
	from invoice_fines
	where fine > 0
	group by
		contract_id,
		paid_date
),
filtered_contracts as (
	select distinct
		c.property_id,
		c.id,
		c.init_date,
		coalesce(c.termination_date, c.expected_end_date) as end_date
	from
		unit_economics.vw_base_contract_costs c
	join filtered_fines ff
    on ff.contract_id = c.id
),
contract_dates as (
	select
		fc.property_id as property_id,
		fc.id,
		fd.dt,
		row_number() over (partition by fc.id order by fd.dt) as rn,
		case when fd.dt > now() then 1 else 0 end as flg_expected
	from
		filtered_contracts fc
	left join
		filtered_dates fd
	on fd.dt between fc.init_date and fc.end_date
),
fines as (
  select
		case when flg_expected = 0 then coalesce(ff.fine,0) else ff.fine end as fine,
		coalesce(ff.paid_date::date, c.dt) as dt,
		c.property_id as property_id,
		c.id,
		avg(case when flg_expected = 0 then coalesce(ff.fine,0) else ff.fine end) filter (where flg_expected=0) over (partition by c.id) as av,
		rn,
		flg_expected
  from contract_dates c
  left join filtered_fines ff
    on ff.contract_id = c.id
    and date_trunc('month',ff.paid_date) = c.dt
)
select
    vbpc.sk_property,
  f.property_id,
	coalesce(fine, gap_fill(av) over (partition by id order by dt)) as vl_delay_fine,
  f.dt as dt_cash_flow,
  f.flg_expected::integer as flg_expected_delay_fine
from fines f
join unit_economics.vw_base_property_costs vbpc
  on vbpc.property_id = f.property_id
    and f.dt between vbpc.min_version_time and vbpc.max_version_time
;