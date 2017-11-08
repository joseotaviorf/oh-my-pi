drop view if exists vw_mgmt_ops_cs_post_sale_costs;
create or replace view vw_mgmt_ops_cs_post_sale_costs as
with cdre_cs_post_sale as (
    select
      "Value" as "value",
      "Month"::date as dre_date
    from files.costs_dre
    where costs_dre."Category" = 'Customer Support (post-sale)'
),
filtered_contracts as (
    select distinct
      property_id,
      init_date::date as start_date,
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
      cps.dre_date as dt_cash_flow,
      cps."value" / (count(fc.property_id) over (partition by cps.dre_date))::double precision as vl_cs_post_sale
    from filtered_contracts fc
    join cdre_cs_post_sale cps
      on cps.dre_date between date_trunc('month', fc.start_date) + interval '1 month'
                        and date_trunc('month', fc.end_date) + interval '1 month'
)
select
  coalesce(vbpc.sk_property, (c.property_id || '001')::bigint) as sk_property,
  c.property_id,
  c.dt_cash_flow,
  c.vl_cs_post_sale
from costs c
left join vw_base_property_costs vbpc
  on vbpc.property_id = c.property_id
    and c.start_date >= vbpc.min_version_time
    and c.end_date <= vbpc.max_version_time
;