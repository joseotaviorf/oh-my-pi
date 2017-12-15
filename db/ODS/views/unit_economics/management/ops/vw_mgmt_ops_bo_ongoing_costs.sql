drop view if exists unit_economics.vw_mgmt_ops_bo_ongoing_costs;
create or replace view unit_economics.vw_mgmt_ops_bo_ongoing_costs as
with cdre_ongoing as (
    select
      dre_value,
      dre_date,
      0 as flg_expected_bo_ongoing
    from unit_economics.vw_base_dre_costs
    where dre_category = 'Back-Office (ongoing)'
),
filtered_contracts as (
    select distinct
      property_id,
      init_date as start_date,
      coalesce(termination_date, expected_end_date)::date as end_date
    from unit_economics.vw_base_contract_costs
    where init_date is not null
      and (termination_date is not null
            or expected_end_date is not null)
),
series as (
	select
		null::double precision as dre_value,
		generate_series((max(dre.dre_date) + interval '1 month')::date,
		    (max(dre.dre_date) + interval '60 month')::date, interval '1 month') as dre_date,
		1 as flg_expected_bo_ongoing
	from cdre_ongoing dre

	union

	select
	    dre_value,
	    dre_date,
	    flg_expected_bo_ongoing
	from cdre_ongoing
),
cdre_ongoing_fc as (
    select
        gap_fill(dre_value) over (order by dre_date) as dre_value,
        dre_date,
        coalesce(flg_expected_bo_ongoing, 1) as flg_expected_bo_ongoing
    from series
),
costs as (
    select
      fc.property_id,
      fc.start_date,
      fc.end_date,
      co.dre_date as dt_cash_flow,
      co.dre_value / (count(fc.property_id) over (partition by co.dre_date))::double precision as vl_bo_ongoing,
      flg_expected_bo_ongoing
    from filtered_contracts fc
    join cdre_ongoing_fc co
      on co.dre_date between date_trunc('month', fc.start_date)  + interval '1 month'
                        and date_trunc('month', fc.end_date) + interval '1 month'
)
select
  coalesce(vbpc.sk_property, (c.property_id || '001')::bigint) as sk_property,
  c.property_id,
  c.dt_cash_flow,
  c.vl_bo_ongoing,
  flg_expected_bo_ongoing
from costs c
left join unit_economics.vw_base_property_costs vbpc
  on vbpc.property_id = c.property_id
    and c.start_date >= vbpc.min_version_time
    and c.end_date <= vbpc.max_version_time
;