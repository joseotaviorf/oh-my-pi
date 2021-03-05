WITH consolidated_google_costs AS (
  WITH filtered_google_costs_no_test_campaigns AS (
    SELECT
      fg.sk_date,
      COALESCE(dgk.campaign_name, dga.campaign_name, dgc.campaign_name, dgv.campaign_name) AS campaign_name,
      COALESCE(dgk.account_name, dga.account_name, dgc.account_name, dgv.account_name) AS account_name,
      COALESCE(dgk.report_type, dga.report_type, dgc.report_type, dgv.report_type) AS report_type,
      COALESCE(gtatf.flag, 'other') AS ad_type,
      CASE WHEN fg.sk_keyword <> - 1 THEN
          dgk.keyword_name || '_' || LOWER(
          LEFT (dgk.match_type, 1))
      ELSE
          CAST(dga.ad_group_name AS STRING)
      END AS utm_term,
      CAST(dga.id_ad AS STRING) AS utm_content,
      fg.desktop_cost,
      fg.mobile_cost,
      fg.total_cost
    FROM
      dw_marketing_costs.fact_google_daily_cost_attributions fg
    LEFT JOIN dw_marketing_costs.dim_google_keyword dgk
      ON dgk.sk_keyword = fg.sk_keyword
    LEFT JOIN dw_marketing_costs.dim_google_ad dga
      ON dga.sk_ad = fg.sk_ad
    LEFT JOIN dw_marketing_costs.dim_google_campaign dgc
      ON dgc.sk_campaign = fg.sk_campaign
    LEFT JOIN dw_marketing_costs.dim_google_video dgv
      ON dgv.sk_video = fg.sk_video
    LEFT JOIN datalake_gsheets_clean.marketing_costs_google_ad_type_flags gtatf
      ON dga.ad_type = gtatf.ad_type
    WHERE
      dgk.is_test_campaign != TRUE
      AND dga.is_test_campaign != TRUE
      AND dgc.is_test_campaign != TRUE
      AND dgv.is_test_campaign != TRUE
      AND gtatf.flag <> 'other'
        OR gtatf.flag IS NULL
      AND SUBSTRING(COALESCE(dgk.campaign_name, dga.campaign_name, dgc.campaign_name, dgv.campaign_name), 1, 5) <> 'ZEBRA'
      AND fg.sk_date >= 20190101
  ),
  formatted_manual_google_costs AS (
    WITH formatted_manual_costs AS (
        SELECT
            REPLACE(REPLACE(REGEXP_REPLACE(LOWER(account_name), '\\P{{ASCII}}.*', ''), ' - ', '_'), ' ', '_') as formatted_account_name,
            campaign_name,
            CAST(DATE_FORMAT(dt_cost, 'yyyyMMdd') AS BIGINT) AS sk_date,
            desktop_cost,
            mobile_cost,
            tablet_cost
        FROM
            datalake_gsheets_clean.marketing_costs_manual_costs_google g
    )
    SELECT
        CASE WHEN formatted_account_name = 'quintoandar_display_and_video' THEN
            'quintoandar_dra'
        ELSE
            formatted_account_name
        END AS account_name,
        campaign_name,
        sk_date,
        desktop_cost,
        mobile_cost,
        tablet_cost
    FROM
        formatted_manual_costs
    WHERE
      sk_date >= 20190101
  )
  SELECT
    COALESCE(m.sk_date, g.sk_date) AS sk_date,
    CASE WHEN m.sk_date IS NOT NULL THEN
        m.campaign_name
    ELSE
        g.campaign_name
    END AS campaign_name,
    CASE WHEN m.sk_date IS NOT NULL THEN
        m.account_name
    ELSE
        g.account_name
    END AS account_name,
    CASE WHEN m.sk_date IS NOT NULL THEN
        m.campaign_name
    ELSE
        g.campaign_name
    END AS utm_campaign,
    CASE WHEN m.sk_date IS NULL THEN
        g.utm_term
    END AS utm_term,
    CASE WHEN m.sk_date IS NULL THEN
        g.utm_content
    END AS utm_content,
    CASE WHEN m.sk_date IS NOT NULL THEN
        m.desktop_cost
    ELSE
        g.desktop_cost
    END AS desktop_cost,
    CASE WHEN m.sk_date IS NOT NULL THEN
        m.mobile_cost
    ELSE
        g.mobile_cost
    END AS mobile_cost,
    g.report_type AS report_type,
    g.ad_type AS ad_type
  FROM
      filtered_google_costs_no_test_campaigns g
  FULL OUTER JOIN formatted_manual_google_costs m ON m.sk_date = g.sk_date
  AND m.account_name = g.account_name
  AND m.campaign_name = g.campaign_name
),
distinct_google_campaigns AS (
  SELECT DISTINCT
      campaign_name,
      account_name
  FROM
      consolidated_google_costs
),
formatted_national_affiliate_historical_costs AS (
  SELECT
      dt_cost,
      campaign,
      cost,
      city_group
  FROM
    datalake_gsheets_clean.marketing_costs_national_affiliate_historical_costs
),
consolidated_google_affiliate_costs AS (
  SELECT DISTINCT
    gcc.sk_date,
    gcc.campaign_name,
    hist.campaign
  FROM
    consolidated_google_costs gcc
  JOIN
    formatted_national_affiliate_historical_costs hist
      ON LOWER(gcc.campaign_name) = LOWER(hist.campaign)
      AND gcc.sk_date = hist.dt_cost
)
SELECT
    'google' AS origin,
    'fact_google_daily_cost_attributions' AS fact_cost,
    hist.campaign,
    hist.city_group AS campaign_city,
    gi.account_name,
    LOWER(hist.campaign) AS campaign_name_l,
    LOWER(gi.account_name) AS account_name_l,
    hist.campaign AS utm_campaign,
    NULL AS utm_term,
    NULL AS utm_content,
    hist.cost AS desktop_cost,
    NULL AS mobile_cost,
    NULL AS other_cost,
    NULL AS total_cost,
    hist.dt_cost
FROM
    formatted_national_affiliate_historical_costs hist
JOIN
    consolidated_google_affiliate_costs hl
      ON hl.sk_date = hist.dt_cost
      AND hl.campaign = hist.campaign
LEFT JOIN distinct_google_campaigns gi
  ON LOWER(gi.campaign_name) = LOWER(hist.campaign)
