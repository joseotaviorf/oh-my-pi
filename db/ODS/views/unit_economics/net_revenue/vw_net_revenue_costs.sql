drop view vw_net_revenue_costs;
---
--- Returns vl_affiliate_commission costs for each first version property
--- Cost: Affiliate Commission on rented properties
--- Cash Flow Date: Date of Payment
---
create or replace view vw_net_revenue_costs as
select
    sk_property,
    property_id,
    dt_cash_flow,
    coalesce(vl_affiliate_commission, 0) as vl_affiliate_commission
from
    vw_net_revenue_commission_costs
;
