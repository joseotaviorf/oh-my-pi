drop view if exists unit_economics.vw_supply_ops_photos_costs;
create or replace view unit_economics.vw_supply_ops_photos_costs as
with cdre_photos as (
    select
      dre_value,
      dre_date
    from unit_economics.vw_base_dre_costs
    where dre_category = 'Listing Photos'
),
filtered_properties as (
   select distinct
      sk_house_listing,
      property_id,
      min_version_time::date as listing_date
    from unit_economics.vw_base_property_costs
    where version = 1
),
costs as (
    select
      fp.sk_house_listing,
      fp.property_id,
      fp.listing_date,
      cp.dre_date as dt_cash_flow,
      cp.dre_value / (count(fp.property_id) over (partition by cp.dre_date))::double precision as vl_photos
    from filtered_properties fp
    join cdre_photos cp
      on cp.dre_date = (date_trunc('month', fp.listing_date) + interval '1 month')::date
)
select
  sk_house_listing,
  property_id,
  make_date(extract(year from dt_cash_flow)::int, extract(month from dt_cash_flow)::int, 5) as dt_cash_flow,
  vl_photos
from costs
;