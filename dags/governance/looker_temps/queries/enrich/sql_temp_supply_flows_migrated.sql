WITH rent_flows AS (
  SELECT
    sk_house_listing_flow,
    sk_lead,
    sk_house_listing,
    sk_user_lead_affiliate,
    sk_region,
    mkt_origin_rent AS mkt_origin,
    mkt_completion_rent AS mkt_completion,
    mkt_channel_rent AS mkt_channel,
    mkt_source_rent AS mkt_source,
    mkt_medium_rent AS mkt_medium,
    sales_company_rent AS sales_company,
    sourcing_ops_rent AS sourcing_ops,
    lead_origin_rent AS lead_origin,
    funnel_drop_reason_rent AS funnel_drop_reason,
    sk_lead_date_rent AS sk_lead_date,
    sk_prospect_date_rent AS sk_prospect_date,
    sk_qualified_date_rent AS sk_qualified_date,
    sk_available_qualified_date_rent AS sk_available_qualified_date,
    sk_opportunity_date_rent AS sk_opportunity_date,
    sk_first_listing_date_rent AS sk_first_listing_date,
    context_lead_rent AS context_lead,
    context_prospect_rent AS context_prospect,
    context_qualified_rent AS context_qualified,
    context_available_qualified_rent AS context_available_qualified,
    context_opportunity_rent AS context_opportunity,
    context_first_listing_rent AS context_first_listing,
    lead_discard_rent AS lead_discard,
    prospect_discard_rent AS prospect_discard,
    prospect_status,
    'Rent' AS origin_table
  FROM dw_datamarts.temp_supply_flows
), sale_flows AS (
  SELECT
    sk_house_listing_flow,
    sk_lead,
    sk_house_listing,
    sk_user_lead_affiliate,
    sk_region,
    mkt_origin_sale AS mkt_origin,
    mkt_completion_sale AS mkt_completion,
    mkt_channel_sale AS mkt_channel,
    mkt_source_sale AS mkt_source,
    mkt_medium_sale AS mkt_medium,
    sales_company_sale AS sales_company,
    sourcing_ops_sale AS sourcing_ops,
    lead_origin_sale AS lead_origin,
    funnel_drop_reason_sale AS funnel_drop_reason,
    sk_lead_date_sale AS sk_lead_date,
    sk_prospect_date_sale AS sk_prospect_date,
    sk_qualified_date_sale AS sk_qualified_date,
    sk_available_qualified_date_sale AS sk_available_qualified_date,
    sk_opportunity_date_sale AS sk_opportunity_date,
    sk_first_listing_date_sale AS sk_first_listing_date,
    context_lead_sale AS context_lead,
    context_prospect_sale AS context_prospect,
    context_qualified_sale AS context_qualified,
    context_available_qualified_sale AS context_available_qualified,
    context_opportunity_sale AS context_opportunity,
    context_first_listing_sale AS context_first_listing,
    lead_discard_sale AS lead_discard,
    prospect_discard_sale AS prospect_discard,
    prospect_status,
    'Sale' AS origin_table
  FROM dw_datamarts.temp_supply_flows
)
SELECT
  *
FROM rent_flows
UNION ALL
SELECT
  *
FROM sale_flows