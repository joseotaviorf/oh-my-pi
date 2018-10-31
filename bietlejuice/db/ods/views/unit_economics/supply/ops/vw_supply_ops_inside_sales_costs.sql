drop view if exists unit_economics.vw_supply_ops_inside_sales_costs;
create or replace view unit_economics.vw_supply_ops_inside_sales_costs as
with cdre_inside_sales as (
    select
      dre_value,
      dre_date
    from unit_economics.vw_base_dre_costs
    where dre_category in ('Inside Sales', 'Inside sales')
),
filtered_properties as (
	select distinct
	    sk_house_listing,
	    property_id,
	    min_version_time::date as listing_date
	from
		unit_economics.vw_base_property_costs base
	left join
		lead_conversion cl
		on cl.imovel_id = base.property_id
	where
		cl.id is not null
		and version = 1
),
costs as (
    select
      fp.sk_house_listing,
      fp.property_id,
      fp.listing_date,
      cis.dre_date as dt_cash_flow,
      cis.dre_value / (count(fp.property_id) over (partition by cis.dre_date))::double precision as vl_inside_sales
    from filtered_properties fp
    join cdre_inside_sales cis
      on cis.dre_date = (date_trunc('month', fp.listing_date) + interval '1 month')::date
)
select
  sk_house_listing,
  property_id,
  dt_cash_flow as dt_cash_flow,
  vl_inside_sales
from costs c
;