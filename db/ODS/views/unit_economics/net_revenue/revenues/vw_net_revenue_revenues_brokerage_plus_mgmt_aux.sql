drop view if exists unit_economics.vw_net_revenue_revenues_brokerage_plus_mgmt_aux;
create or replace view unit_economics.vw_net_revenue_revenues_brokerage_plus_mgmt_aux as
select
    coalesce(br.sk_property, mg.sk_property) as sk_property,
    coalesce(br.property_id, mg.property_id) as property_id,
    coalesce(br.vl_brokerage_fee, 0) + coalesce(mg.vl_management_fee, 0) as brokerage_plus_mgmt,
    coalesce(br.dt_cash_flow, mg.dt_cash_flow) as dt_cash_flow,
    coalesce(mg.flg_expected_management_fee, 0) as flg_expected_management_fee,
    coalesce(br.flg_expected_brokerage_fee, 0) as flg_expected_brokerage_fee
  from unit_economics.vw_net_revenue_revenues_brokerage_fee br
  full outer join unit_economics.vw_net_revenue_revenues_mgmt_fee mg
    on br.sk_property = mg.sk_property
       and br.dt_cash_flow = mg.dt_cash_flow
  where br.vl_brokerage_fee > 0
    or mg.vl_management_fee > 0
;