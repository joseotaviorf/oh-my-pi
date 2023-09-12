SELECT
    accrual_year_month,
    SUM(rental_management) AS rental_management,
    SUM(rental_brokerage) AS rental_brokerage,
    SUM(partner_share_management) AS partner_share_management,
    SUM(partner_share_brokerage) AS partner_share_brokerage,
    SUM(insurance_commission) insurance_commission,
    SUM(late_payments) AS late_payments,
    SUM(addons_guarantee) addons_guarantee,
    SUM(addons_service_fee) AS addons_service_fee,
    SUM(addons_lra) AS addons_lra,
    SUM(addons_reserve) AS addons_reserve,
    SUM(addons_mra) AS addons_mra,
    SUM(addons_bfi) AS addons_bfi,
    SUM(addons_ccp) AS addons_ccp,
    SUM(addons_new_business_revenue) addons_new_business_revenue,
    SUM(addons_revenue_total) addons_revenue,
    SUM(agents_commission) AS agents_commission,
    SUM(affiliates_commission) AS affiliates_commission,
    SUM(revenue_share_total) revenue_share_total,
    SUM(gross_revenue) gross_revenue,
    SUM(net_revenue_pre_taxes) net_revenue_pre_taxes
 FROM
    dw_rental_contribution_margin.fact_house_listing_revenues
 WHERE
    (country_code = 'BR' or country_code='Undefined')
 GROUP BY
     1
