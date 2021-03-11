WITH formatted_historic_affiliates_national_campaigns_cost AS (
  SELECT
      dt_cost,
      campaign,
      cost,
      city_group
  FROM
    datalake_gsheets_clean.marketing_costs_national_affiliate_historical_costs
),
facebook_info AS (
    SELECT DISTINCT
        campaign_name,
        account_name
    FROM
        dw_marketing_costs.dim_facebook_ad
),
facebook_historical_affiliate_campaigns AS (
    SELECT DISTINCT
        ff.sk_date,
        df.campaign_name,
        hist.campaign
    FROM
        dw_marketing_costs.fact_facebook_daily_cost_attributions ff
        JOIN dw_marketing_costs.dim_facebook_ad df ON ff.sk_ad = df.sk_ad
            AND df.is_test_campaign = false
        JOIN formatted_historic_affiliates_national_campaigns_cost hist ON LOWER(df.campaign_name) = LOWER(hist.campaign)
            AND ff.sk_date = hist.dt_cost
    WHERE
        ff.sk_date >= 20190101
        AND SUBSTRING(df.campaign_name, 1, 5) <> 'ZEBRA'
)
SELECT
    hist.dt_cost AS sk_cost_date,
    'facebook' AS origin,
    'fact_facebook_daily_cost_attributions' AS fact_cost,
    hist.campaign,
    hist.city_group AS campaign_city,
    df.account_name,
    LOWER(hist.campaign) AS campaign_name_l,
    LOWER(df.account_name) AS account_name_l,
    hist.campaign AS utm_campaign,
    CAST(NULL AS STRING) AS utm_term,
    CAST(NULL AS STRING) AS utm_content,
    hist.cost AS desktop_cost,
    CAST(NULL AS DOUBLE) AS mobile_cost,
    CAST(NULL AS DOUBLE) AS other_cost,
    CAST(NULL AS DOUBLE) AS total_cost
FROM
    formatted_historic_affiliates_national_campaigns_cost hist
    JOIN facebook_historical_affiliate_campaigns hl ON hl.sk_date = hist.dt_cost
        AND hl.campaign = hist.campaign
    LEFT JOIN facebook_info df
      ON LOWER(df.campaign_name) = LOWER(hist.campaign)
