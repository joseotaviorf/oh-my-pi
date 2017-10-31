drop view if exists vw_liquidity_ops_cs_pre_sale_costs;
create or replace view vw_liquidity_ops_cs_pre_sale_costs as
with cdre_cs_pre_sale as (
    select
      "Value" as "value",
      "Month"::date as dre_date
    from files.costs_dre
    where costs_dre."Category" = 'Customer Support (pre-sale)'
),
filtered_properties as (
    select distinct
      sk_property,
      property_id,
      publication_date::date,
      min_version_time::date,
      max_version_time::date
    from vw_base_property_costs
    where last_status_version = 'publicado'
),
costs as (
    select
      fp.sk_property,
      fp.property_id,
      cps.dre_date as dt_cash_flow,
      cps."value" / (count(fp.property_id) over (partition by cps.dre_date))::double precision as vl_cs_pre_sale
    from filtered_properties fp
    join cdre_cs_pre_sale cps
      on
         case
            when fp.min_version_time = '1900-01-01' and fp.max_version_time = '2300-01-01'
              then cps.dre_date = date_trunc('month', fp.publication_date) + interval '1 month'
            else cps.dre_date between date_trunc('month', fp.min_version_time) + interval '1 month'
                        and date_trunc('month', fp.max_version_time) + interval '1 month'
         end
)
select
  vbpc.sk_property,
  c.property_id,
  c.dt_cash_flow,
  c.vl_cs_pre_sale
from costs c
join vw_base_property_costs vbpc
  on vbpc.sk_property = c.sk_property
;

