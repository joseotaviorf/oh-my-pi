drop view if exists unit_economics.vw_supply_ops_costs;
create or replace view unit_economics.vw_supply_ops_costs as
select
  coalesce(vsopc.sk_house_listing, vsoisc.sk_house_listing) as sk_house_listing,
  coalesce(vsopc.property_id, vsoisc.property_id) as property_id,
  coalesce(vsopc.dt_cash_flow, vsoisc.dt_cash_flow) as dt_cash_flow,
  coalesce(vsopc.vl_photos, 0) as vl_photos,
  coalesce(vsoisc.vl_inside_sales, 0) as vl_inside_sales
from unit_economics.supply_ops_photos_costs vsopc
full outer join unit_economics.supply_ops_inside_sales_costs vsoisc
  on vsoisc.sk_house_listing = vsopc.sk_house_listing
     and vsoisc.dt_cash_flow = vsopc.dt_cash_flow
;