with demand_classifieds as (
  select
      to_hex(md5(to_utf8(source))) as sk_classified,
      source as name,
      current_timestamp as ts_load
    from datalake_clean.marketing_demand_classifieds_costs
),
supply_classifieds as (
  select
      to_hex(md5(to_utf8(source))) as sk_classified,
      source as name,
      current_timestamp as ts_load
    from datalake_clean.marketing_supply_classifieds_costs
)
select
  sk_classified,
  name,
  ts_load
from demand_classifieds
union
select
  sk_classified,
  name,
  ts_load
from supply_classifieds