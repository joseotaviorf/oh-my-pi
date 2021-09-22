--GOOGLE

WITH 
fg AS (
    SELECT 
        sk_date,
        COALESCE(
        nullif(sk_keyword, -1), 
        nullif(sk_ad, -1),
        nullif(sk_campaign, -1),
        nullif(sk_video, -1)) as sk,
        sk_keyword,
        impressions,
        total_clicks,
        total_cost
    FROM
        marketing_costs.fact_google_daily_cost_attributions
)

SELECT DISTINCT
    fg.sk_date,
    'google' origin,
    COALESCE(dgk.account_name, dga.account_name, dgc.account_name) AS account_name,
    COALESCE(dgk.campaign_name, dga.campaign_name, dgc.campaign_name) AS utm_campaign,
    CASE 
     WHEN fg.sk_keyword <> - 1 THEN dgk.keyword_name || '_' || LOWER(LEFT(dgk.match_type, 1))
     ELSE CAST(dga.ad_group_name AS VARCHAR)
    END AS utm_term,
    CAST(dga.id_ad AS VARCHAR) AS utm_content,
    fg.impressions impressions,
    fg.total_clicks clicks,
    0 AS reach,
    fg.total_cost as cost
FROM    
    fg
LEFT JOIN 
    marketing_costs.dim_google_keyword dgk 
    ON dgk.sk_keyword = fg.sk
 LEFT JOIN 
    marketing_costs.dim_google_ad dga 
    ON dga.sk_ad = fg.sk
LEFT JOIN 
    marketing_costs.dim_google_campaign dgc 
    ON dgc.sk_campaign = fg.sk
LEFT JOIN 
    marketing_costs.dim_google_video dgv 
    ON dgv.sk_video = fg.sk
LEFT JOIN 
    datalake_raw.gsheets_taxonomy_ad_type_flags gtatf 
    ON dga.ad_type = gtatf.ad_type
    
UNION ALL

--FACEBOOK

SELECT
    ff.sk_date,
    'facebook' origin,
    df.account_name,
    df.campaign_name AS utm_campaign,
    df.adset_name AS utm_term,
    df.ad_name AS utm_content,
    ff.total_impressions impressions,
    ff.total_link_clicks clicks,
    ff.total_reach reach,
    ff.total_spend cost
FROM
    marketing.fact_facebook_daily_cost_attributions ff
LEFT JOIN 
    marketing.dim_facebook_ad df 
    ON ff.sk_ad = df.sk_ad
