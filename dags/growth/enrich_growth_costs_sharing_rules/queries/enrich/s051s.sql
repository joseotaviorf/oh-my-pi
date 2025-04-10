-----------------------------------------------------------------------------------------------------------
-- Sharing rule for rent and sale leads generated only on cities where we have the respective operations --
-----------------------------------------------------------------------------------------------------------
SELECT 
  fse.sk_date AS id_date,
  '{id_rule}' AS id_rule,
  'supply' AS funnel_side, 
  NULL::STRING AS country_code,
  NULL::STRING AS city_group,
  SUBSTRING(dal.nm_campaign, INSTR(dal.nm_campaign, '.') + 1) AS utm_campaign_modified,
  fse.nm_business_context AS business_context,
  COUNT(DISTINCT fse.sk_supply)
    /CAST(NULLIF(SUM(COUNT(DISTINCT fse.sk_supply)) OVER(PARTITION BY fse.sk_date, fse.utm_campaign), 0) AS DOUBLE) AS share 
FROM dw_growth.fact_supply_events fse
LEFT JOIN dw_growth.dim_acquisition_lead AS dal
    ON fse.sk_acquisition_lead = dal.sk_acquisition_lead
WHERE nm_media_setup LIKE '%hybr%' -- Only hybrid campaings
  AND sk_funnel_step = 9 -- prospects
GROUP BY 1,2,3,4,5,6,7,fse.utm_campaign
