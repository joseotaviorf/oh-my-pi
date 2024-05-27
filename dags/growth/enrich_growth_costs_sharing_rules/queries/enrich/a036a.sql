------------------------------------------------------------------------------------------
-- Sharing rule for prospects indicated by affiliates that registered at the same month --
------------------------------------------------------------------------------------------
WITH 
-------------------------------------------------------------------------------------------
-- This CTE aims to compute the outcome that will serve as the basis for cost allocation --
-------------------------------------------------------------------------------------------
conversion_metrics AS (
SELECT
    dd.date,
    dd.id_date,
    dr.country_code,
    dr.city_group,
    NULL AS utm_campaign,
    fse.nm_business_context as business_context,
    COUNT(DISTINCT fse.sk_supply) AS metric 
FROM dw_growth.fact_supply_events AS fse 
LEFT JOIN dw_growth.dim_affiliate_tracking AS dat
    ON fse.sk_user_affiliate = dat.sk_user_affiliate
        AND fse.ts_first_event_date >= dat.ts_started 
        AND fse.ts_first_event_date < COALESCE(dat.ts_ended, CAST('2099-12-31' AS TIMESTAMP))
LEFT JOIN datalake_quintoandar.aux_date AS dd
    ON CAST(fse.sk_date AS INTEGER) = dd.id_date
LEFT JOIN datalake_quintoandar.aux_date AS ddaf
    ON CAST(dat.sk_start_date AS INTEGER) = ddaf.id_date
LEFT JOIN datalake_region.region AS dr
    ON fse.sk_region = dr.id
WHERE fse.sk_funnel_step = 9
    AND dr.has_rent_operation
    AND fse.nm_business_context = 'RENT'
    AND dat.version = 1 --somente novos usuários
    AND dd.month_start = ddaf.month_start --prospects no mesmo mês dos novos usuários
GROUP BY 1,2,3,4,5,6
UNION ALL 
SELECT
    dd.date,
    dd.id_date,
    dr.country_code,
    dr.city_group,
    NULL AS utm_campaign,
    fse.nm_business_context as business_context,
    COUNT(DISTINCT fse.sk_supply) AS metric 
FROM dw_growth.fact_supply_events AS fse 
LEFT JOIN dw_growth.dim_affiliate_tracking AS dat
    ON fse.sk_user_affiliate = dat.sk_user_affiliate
        AND fse.ts_first_event_date >= dat.ts_started 
        AND fse.ts_first_event_date < COALESCE(dat.ts_ended, CAST('2099-12-31' AS TIMESTAMP))
LEFT JOIN datalake_quintoandar.aux_date AS dd
    ON CAST(fse.sk_date AS INTEGER) = dd.id_date
LEFT JOIN datalake_quintoandar.aux_date AS ddaf
    ON CAST(dat.sk_start_date AS INTEGER) = ddaf.id_date
LEFT JOIN datalake_region.region AS dr
    ON fse.sk_region = dr.id
WHERE fse.sk_funnel_step = 9
    AND dr.has_sale_operation
    AND fse.nm_business_context = 'SALE'
    AND dat.version = 1 --somente novos usuários
    AND dd.month_start = ddaf.month_start --prospects no mesmo mês dos novos usuários
GROUP BY 1,2,3,4,5,6
),
-----------------------------------------------------------------------------------------------
-- This CTE seeks to calculate the moving average of the outcomes from the last 7 days, 
-- which will be utilized in the fallback CTE in case there is a lack of outcome on that day.
-----------------------------------------------------------------------------------------------
moving_average AS ( 
  SELECT 
    adt.id_date,   
    cm.country_code,
    cm.city_group, 
    cm.utm_campaign,
    cm.business_context,
    SUM(cm.metric) AS metric
  FROM conversion_metrics AS cm 
  INNER JOIN datalake_quintoandar.aux_date AS adt
    ON cm.date BETWEEN adt.date - INTERVAL '6' DAY AND adt.date
    AND adt.date <= CURRENT_DATE()
  GROUP BY 1,2,3,4,5
), 
--------------------------------------------------------------------
-- This CTE calculates the share based on the moving average CTE. --
--------------------------------------------------------------------
fall_back AS (
  SELECT 
      mm.id_date,
      mm.country_code,
      mm.city_group,
      mm.utm_campaign, 
      mm.business_context,
      FLOAT(SUM(mm.metric))/NULLIF(SUM(SUM(mm.metric)) OVER(PARTITION BY mm.id_date, mm.utm_campaign), 0) AS share
  FROM moving_average AS mm
  WHERE TRUE 
  GROUP BY 1,2,3,4,5
), 
-----------------------------------------------------------------------
-- This CTE calculates the share of the segmentation day's outcomes. --
-----------------------------------------------------------------------
actual AS ( 
  SELECT 
      cm.id_date,
      cm.country_code,
      cm.city_group,
      cm.utm_campaign, 
      cm.business_context,
      FLOAT(SUM(cm.metric))/NULLIF(SUM(SUM(cm.metric)) OVER(PARTITION BY cm.id_date, cm.utm_campaign), 0) AS share
  FROM conversion_metrics AS cm
  GROUP BY 1,2,3,4,5
), 
-----------------------------------------------------------------------------------------------
-- This CTE identifies whether there was an outcome on that specific day 
-- in order to use its results as a condition to determine which outcomes will be utilized, 
-- whether it's the outcome of the day or the moving average 
-----------------------------------------------------------------------------------------------
validacao AS (
SELECT
	adt.id_date,
  cm.utm_campaign, 
	SUM(cm.metric) AS validador
FROM datalake_quintoandar.aux_date AS adt
LEFT JOIN conversion_metrics AS cm
  ON cm.id_date = adt.id_date
GROUP BY 1,2
)
-------------------------------------------------------------------------------------------------------
-- Applying share factor from the correct table based on status: it has or hasn't result on that day --
-------------------------------------------------------------------------------------------------------
SELECT DISTINCT
	v.id_date,
	'{id_rule}' AS id_rule,
  'supply' AS funnel_side, 
  IF(validador > 0, a.country_code, fb.country_code) AS country_code,
  IF(validador > 0, a.city_group, fb.city_group) AS city_group, 
  IF(validador > 0, a.utm_campaign, fb.utm_campaign) AS utm_campaign, 
  IF(validador > 0, a.business_context, fb.business_context) AS business_context, 
  IF(validador > 0, a.share, fb.share) AS share
FROM validacao v
LEFT JOIN actual AS a
	ON a.id_date = v.id_date
  AND a.utm_campaign = v.utm_campaign
LEFT JOIN fall_back AS fb
	ON fb.id_date = v.id_date
  AND fb.utm_campaign = v.utm_campaign