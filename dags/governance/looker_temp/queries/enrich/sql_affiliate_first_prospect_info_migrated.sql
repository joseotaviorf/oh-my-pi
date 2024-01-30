WITH funnel_dates_rent AS (
  SELECT
    f.sk_user_lead_affiliate AS sk_user,
    f.sk_prospect_date,
    f.sk_lead,
    ROW_NUMBER() OVER (PARTITION BY f.sk_user_lead_affiliate ORDER BY sk_prospect_date ASC NULLS LAST) AS rn_prospect_date
  FROM dw_public.fact_house_listing_flows AS f
  WHERE
    f.sk_user_lead_affiliate > 0 AND f.sk_prospect_date > 0
), funnel_dates_sale AS (
  SELECT
    f.sk_user_lead_affiliate AS sk_user,
    f.sk_prospect_date,
    f.sk_lead,
    ROW_NUMBER() OVER (PARTITION BY f.sk_user_lead_affiliate ORDER BY sk_prospect_date ASC NULLS LAST) AS sl_prospect_date
  FROM dw_sale.fact_listing_flows AS f
  WHERE
    f.sk_user_lead_affiliate > 0 AND f.sk_prospect_date > 0
), first_funnel_date_rent AS (
  SELECT
    sk_user,
    sk_prospect_date,
    sk_lead
  FROM funnel_dates_rent
  WHERE
    rn_prospect_date = 1
), first_funnel_date_sale AS (
  SELECT
    sk_user,
    sk_prospect_date,
    sk_lead
  FROM funnel_dates_sale
  WHERE
    sl_prospect_date = 1
), first_date_general AS (
  SELECT
    *
  FROM first_funnel_date_rent
  UNION ALL
  SELECT
    *
  FROM first_funnel_date_sale
), first_funnel_date AS (
  SELECT
    sk_user,
    sk_prospect_date,
    sk_lead,
    ROW_NUMBER() OVER (PARTITION BY sk_user ORDER BY sk_prospect_date ASC NULLS LAST) AS rn_prospect_date
  FROM first_date_general
)
SELECT
  sk_user,
  sk_prospect_date,
  sk_lead
FROM first_funnel_date
WHERE
  rn_prospect_date = 1