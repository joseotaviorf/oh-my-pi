drop view if exists vw_supply_ops_costs;
create or replace view vw_supply_ops_costs as
select
  sk_property,
  property_id,
  dt_cash_flow,
  sum(vl_photos) as vl_photos,
  sum(vl_inside_sales) as vl_inside_sales
from (
  select
    sk_property,
    property_id,
    dt_cash_flow,
    vl_photos,
    0 as vl_inside_sales
  from vw_supply_ops_photos_costs

  union all

  select
    sk_property,
    property_id,
    dt_cash_flow,
    0 as vl_photos,
    vl_inside_sales
  from vw_supply_ops_inside_sales_costs
) supply_ops
group by sk_property, property_id, dt_cash_flow
;
