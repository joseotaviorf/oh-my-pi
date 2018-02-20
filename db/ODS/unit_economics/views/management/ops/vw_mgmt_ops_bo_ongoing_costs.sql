drop view if exists unit_economics.vw_mgmt_ops_bo_ongoing_costs;
create or replace view unit_economics.vw_mgmt_ops_bo_ongoing_costs as
with cdre_ongoing as (
    select
      dre_value,
      dre_date
    from unit_economics.vw_base_dre_costs
    where dre_category = 'Back-Office (ongoing)'
),
filtered_contracts_prev as (
    select distinct
      property_id,
      init_date as start_date,
      coalesce(termination_date, expected_end_date)::date as end_date
    from unit_economics.vw_base_contract_costs
    where init_date is not null
      and (termination_date is not null
            or expected_end_date is not null)
),
filtered_contract as (
    select distinct
      fc.property_id,
      fc.start_date,
      fc.end_date,
      date_trunc('month', dd."date")::date as dt_cash_flow
    from dim_date dd
    join filtered_contracts_prev fc
        on date_trunc('month', dd."date") between date_trunc('month', fc.start_date)  + interval '1 month'
                        and date_trunc('month', fc.end_date) + interval '1 month'
),
costs as (
    select distinct
      fc.property_id,
      fc.start_date,
      fc.end_date,
      fc.dt_cash_flow,
      co.dre_value,
      (count(fc.property_id) over (partition by fc.dt_cash_flow)),
      co.dre_value / (count(fc.property_id) over (partition by fc.dt_cash_flow))::double precision as vl_bo_ongoing,
      (dre_value is null)::int as flg_expected_bo_ongoing
    from filtered_contract fc
    left join cdre_ongoing co
      on co.dre_date = fc.dt_cash_flow
),
result as (
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
),
m_avg_prev as (
    select distinct
        dt_cash_flow,
        avg(vl_bo_ongoing) over (partition by dt_cash_flow order by dt_cash_flow) as _avg1
    from result
    order by dt_cash_flow asc
),
last_value as (
    select
        dt_cash_flow,
        case
            when _avg1 is null
                and avg(_avg1) over (rows between 3 preceding and 1 preceding) is not null
                and lag(_avg1) over () is not null
                and lead(_avg1) over () is null
              then avg(_avg1) over (rows between 3 preceding and 1 preceding)
            else _avg1
        end as m_avg
    from m_avg_prev
),
last_value_gap_fill as (
    select
        dt_cash_flow,
        coalesce(m_avg, gap_fill(m_avg) over ()) as new_value
    from last_value
)
select
    r.sk_property,
    r.property_id,
    r.dt_cash_flow,
    r.flg_expected_bo_ongoing,
    lv.new_value as vl_bo_ongoing
from result r
join last_value_gap_fill lv
    on r.dt_cash_flow = lv.dt_cash_flow
;