drop view if exists unit_economics.vw_mgmt_ops_cs_post_sale_costs;
create or replace view unit_economics.vw_mgmt_ops_cs_post_sale_costs as
with cdre_cs_post_sale as (
    select
      dre_value,
      dre_date
    from unit_economics.vw_base_dre_costs
    where dre_category = 'Customer Support (post-sale)'
),
qt_nulls as (
  select
    property_id,
    dt,
    sum(qt) as qt
  from unit_economics.vw_base_ticket_task
  where property_id = -1
    and group_name = 'Customer Support (post-sale)'
  group by property_id, dt
),
calculated_qt as (
  select
    property_id,
    dt,
    qt,
    avg(qt) over() as _avg
  from unit_economics.vw_base_ticket_task
  where group_name = 'Customer Support (post-sale)'
    and property_id != -1
),
filtered_contracts_prev as (
    select distinct
      imovel_id as property_id,
      "dataInicio" as start_date,
      (max(coalesce("dataRescisao", "dataFimContratoPrevisto")) over w)::date as end_date
    from contract c
    where tipo = 'FullService'
      and "dataInicio" is not null
      and ("dataRescisao" is not null
            or "dataFimContratoPrevisto" is not null)
    window w as (partition by imovel_id)
),
<<<<<<< Updated upstream
=======
series as (
	select
		null::double precision as dre_value,
		generate_series((max(dre.dre_date) + interval '1 month')::date,
		    (max(dre.dre_date) + interval '60 month')::date, interval '1 month') as dre_date
	from cdre_cs_post_sale dre

	union

	select dre_value, dre_date
	from cdre_cs_post_sale
),
cdre_cs_post_sale_fc as (
    select
        gap_fill(dre_value) over (order by dre_date) as dre_value,
        dre_date
    from series
),
>>>>>>> Stashed changes
filtered_contracts as (
  select distinct
    fcp.property_id,
    cps.dre_date - interval '1 month' as dt,
    (date_part('year',  cps.dre_date) - date_part('year', start_date)) * 12 +
              (date_part('month',  cps.dre_date) - date_part('month', start_date)) as months_after_init
  from filtered_contracts_prev fcp
    join cdre_cs_post_sale cps
      on cps.dre_date between date_trunc('month', fcp.start_date) + interval '1 month'
                        and date_trunc('month', fcp.end_date) + interval '1 month'
),
ratio as (
  select distinct
    fc.dt,
    qn.qt / count(fc.property_id) over (partition by fc.dt) as qt,
    fc.months_after_init
  from filtered_contracts fc
  left join qt_nulls qn
    on fc.dt = qn.dt
),
gen_contracts as (
	select distinct
		fc.property_id,
		fc.dt,
<<<<<<< Updated upstream
		r.qt as qt_gen
	from
  	filtered_contracts fc
  left join ratio r
  	on fc.dt = r.dt
=======
		r.qt as qt,
		avg(r.qt) over () as _avg,
		fc.months_after_init
	from filtered_contracts fc
    left join ratio r
  	    on fc.dt = r.dt
>>>>>>> Stashed changes
),
calculated as (
    select distinct
        cqt.property_id,
        cqt.dt,
        cqt.qt,
        avg(qt) over (partition by property_id) as _avg
    from calculated_qt cqt
),
spec_gen_prev as (
  select
    coalesce(cc.property_id, gc.property_id) as property_id,
    coalesce(cc.dt, gc.dt) as dt,
    coalesce(cc.qt, 0) + coalesce(gc.qt, 0) as qt,
    coalesce(gc._avg, 0) + (gap_fill(cc._avg) over (partition by gc.property_id order by gc.dt) * (0.93 ^ gc.months_after_init)) as _avg,
    gc.months_after_init
  from calculated cc
  full outer join gen_contracts gc
    on cc.property_id = gc.property_id
        and gc.dt = cc.dt
),
<<<<<<< Updated upstream
espec_gen as (
	select
		property_id,
		dt,
		sum(qt) as qt
	from espec_gen_prev
	group by
		property_id, dt
=======
spec_gen as (
	select distinct
		property_id,
		dt,
		case
		    when qt = 0
		        then coalesce(_avg, 0)
		    else coalesce(qt, _avg)
		end as qt,
		case
		    when qt = 0 and _avg is not null
		        then 1
		    else 0
		end as flg_expected_cs_post_sale
	from spec_gen_prev
>>>>>>> Stashed changes
),
tt_costs as (
    select distinct
      eg.property_id,
      eg.dt,
      cps.dre_date as dt_cash_flow,
<<<<<<< Updated upstream
      cps.dre_value * eg.qt / (sum(eg.qt) over (partition by cps.dre_date))::double precision as vl_cs_post_sale
    from espec_gen eg
    join cdre_cs_post_sale cps
      on cps.dre_date = eg.dt + interval '1 month'
=======
      cps.dre_value * eg.qt / (sum(eg.qt) over (partition by cps.dre_date))::double precision as vl_cs_post_sale,
      flg_expected_cs_post_sale
    from spec_gen eg
    join cdre_cs_post_sale_fc cps
      on cps.dre_date = eg.dt + interval '1 month'
    where eg.qt > 0
>>>>>>> Stashed changes
),
contract_costs as (
    select
      fc.property_id,
      fc.dt,
      cps.dre_date as dt_cash_flow,
      cps.dre_value / (count(fc.property_id) over (partition by cps.dre_date))::double precision as vl_cs_post_sale
    from filtered_contracts fc
    join cdre_cs_post_sale cps
      on cps.dre_date = fc.dt
),
full_costs as (
  select distinct
<<<<<<< Updated upstream
    property_id,
    dt,
    dt_cash_flow,
    vl_cs_post_sale
  from tt_costs
  where dt = dt_cash_flow

  union

  select distinct
    property_id,
    dt,
    dt_cash_flow,
    vl_cs_post_sale
  from contract_costs
  where dt = dt_cash_flow
=======
    coalesce(tt.property_id, cc.property_id) as property_id,
    coalesce(tt.dt, cc.dt) as dt,
    coalesce(tt.dt_cash_flow, cc.dt_cash_flow) as dt_cash_flow,
    coalesce(tt.vl_cs_post_sale, cc.vl_cs_post_sale) as vl_cs_post_sale,
    coalesce(tt.flg_expected_cs_post_sale, 0) as flg_expected_cs_post_sale
  from tt_costs tt
  full outer join contract_costs cc
    on tt.property_id = cc.property_id and tt.dt = cc.dt
        and tt.dt_cash_flow = cc.dt_cash_flow
>>>>>>> Stashed changes
)
select
  coalesce(vbpc.sk_property, (fc.property_id || '001')::bigint) as sk_property,
  fc.property_id,
  fc.dt_cash_flow,
  fc.vl_cs_post_sale,
  0 as flg_expected
from full_costs fc
left join unit_economics.vw_base_property_costs vbpc
  on vbpc.property_id = fc.property_id
    and fc.dt - interval '1 month' between vbpc.min_version_time and vbpc.max_version_time
;