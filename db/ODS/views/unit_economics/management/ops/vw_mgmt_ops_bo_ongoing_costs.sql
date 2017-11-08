drop view if exists vw_mgmt_ops_bo_ongoing_costs;
create or replace view vw_mgmt_ops_bo_ongoing_costs as
with cdre_ongoing as (
    select
      "Value" as "value",
      "Month"::date as dre_date
    from files.costs_dre
    where costs_dre."Category" = 'Back-Office (ongoing)'
),
filtered_contracts as (
    select distinct
      property_id,
      init_date as start_date,
      coalesce(termination_date, expected_end_date)::date as end_date
    from vw_base_contract_costs
    where init_date is not null
      and (termination_date is not null
            or expected_end_date is not null)
),
costs as (
    select
      fc.property_id,
      fc.start_date,
      fc.end_date,
      co.dre_date as dt_cash_flow,
      co."value" / (count(fc.property_id) over (partition by co.dre_date))::double precision as vl_bo_ongoing
    from filtered_contracts fc
    join cdre_ongoing co
      on co.dre_date between date_trunc('month', fc.start_date)  + interval '1 month'
                        and date_trunc('month', fc.end_date) + interval '1 month'
)
select
  coalesce(vbpc.sk_property, (c.property_id || '001')::bigint) as sk_property,
  c.property_id,
  c.dt_cash_flow,
  c.vl_bo_ongoing
from costs c
left join vw_base_property_costs vbpc
  on vbpc.property_id = c.property_id
    and c.start_date >= vbpc.min_version_time
    and c.end_date <= vbpc.max_version_time
;