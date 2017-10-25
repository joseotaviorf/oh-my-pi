drop view if exists vw_mgmt_ops_costs;
create or replace view vw_mgmt_ops_costs as
select
  coalesce(offboarding.sk_property, onboarding.sk_property, ongoing.sk_property, collections.sk_property, post_sale.sk_property) as sk_property,
  coalesce(offboarding.property_id, onboarding.property_id, ongoing.property_id, collections.property_id, post_sale.property_id) as property_id,
  coalesce(offboarding.dt_cash_flow, onboarding.dt_cash_flow, ongoing.dt_cash_flow, collections.dt_cash_flow, post_sale.dt_cash_flow) as dt_cash_flow,
  coalesce(offboarding.vl_bo_offboarding, 0) as vl_bo_offboarding,
  coalesce(onboarding.vl_bo_onboarding, 0) as vl_bo_onboarding,
  coalesce(ongoing.vl_bo_ongoing, 0) as vl_bo_ongoing,
  coalesce(collections.vl_collections, 0) as vl_collections,
  coalesce(post_sale.vl_cs_post_sale, 0) as vl_cs_post_sale

from vw_mgmt_ops_bo_offboarding_costs offboarding

full outer join vw_mgmt_ops_bo_onboarding_costs onboarding
  on onboarding.sk_property = offboarding.sk_property
     and onboarding.dt_cash_flow = offboarding.dt_cash_flow

full outer join vw_mgmt_ops_bo_ongoing_costs ongoing
  on ongoing.sk_property = offboarding.sk_property
     and ongoing.dt_cash_flow = offboarding.dt_cash_flow

full outer join vw_mgmt_ops_collections_costs collections
  on collections.sk_property = offboarding.sk_property
     and collections.dt_cash_flow = offboarding.dt_cash_flow

full outer join vw_mgmt_ops_cs_post_sale_costs post_sale
  on post_sale.sk_property = offboarding.sk_property
     and post_sale.dt_cash_flow = offboarding.dt_cash_flow
;
