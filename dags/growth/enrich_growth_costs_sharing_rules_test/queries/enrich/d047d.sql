WITH 
-------------------------------------------------------------------------------------------
-- This CTE aims to compute the outcome that will serve as the basis for cost allocation --
-------------------------------------------------------------------------------------------
conversion_metrics AS (
  SELECT
    adt.date, 
    adt.id_date,
    dr.country_code, 
    dr.city_group, 
    SUBSTRING(fdpe.utm_campaign, INSTR(fdpe.utm_campaign, '.') + 1) AS utm_campaign_modified,
    LOWER(fdpe.business_context) AS business_context,
    COUNT(DISTINCT 
      CASE WHEN fdpe.event_name = 'USER FIRST ACTIVATION' THEN fdpe.id_prospect 
      ELSE NULL END) + 
    COUNT(DISTINCT 
      CASE WHEN fdpe.event_name = 'USER RECOVERY' THEN fdpe.id_prospect 
      ELSE NULL END) AS metric
  FROM datalake_demand_flows.prospect_daily_results AS fdpe 
  LEFT JOIN datalake_region.region AS dr
    ON fdpe.id_region = dr.id
  LEFT JOIN datalake_quintoandar.aux_date AS adt
    ON fdpe.id_event_date = adt.id_date
  WHERE TRUE 
    AND LOWER(fdpe.business_context) = 'sale'
    AND dr.country_code = 'BR'
    AND (fdpe.utm_campaign LIKE 'd047d%'
      OR fdpe.utm_campaign LIKE 'ZEBRA%')
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
    cm.utm_campaign_modified,
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
      mm.utm_campaign_modified, 
      mm.business_context,
      FLOAT(SUM(mm.metric))/NULLIF(SUM(SUM(mm.metric)) OVER(PARTITION BY mm.id_date, mm.utm_campaign_modified), 0) AS share
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
      cm.utm_campaign_modified, 
      cm.business_context,
      FLOAT(SUM(cm.metric))/NULLIF(SUM(SUM(cm.metric)) OVER(PARTITION BY cm.id_date, cm.utm_campaign_modified), 0) AS share
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
  cm.utm_campaign_modified, 
	SUM(cm.metric) AS validador
FROM datalake_quintoandar.aux_date AS adt
LEFT JOIN conversion_metrics AS cm
  ON cm.id_date = adt.id_date
WHERE TRUE 
  AND adt.YEAR >= 2023
GROUP BY 1,2
)
-------------------------------------------------------------------------------------------------------
-- Applying share factor from the correct table based on status: it has or hasn't result on that day --
-------------------------------------------------------------------------------------------------------
SELECT DISTINCT
	v.id_date,
	'{id_rule}' AS id_rule,
  'demand' AS funnel_side, 
  IF(validador > 0, a.country_code, fb.country_code) AS country_code,
  IF(validador > 0, a.city_group, fb.city_group) AS city_group, 
  IF(validador > 0, a.utm_campaign_modified, fb.utm_campaign_modified) AS utm_campaign_modified, 
  IF(validador > 0, a.business_context, fb.business_context) AS business_context, 
  IF(validador > 0, a.share, fb.share) AS share
FROM validacao v
LEFT JOIN actual AS a
	ON a.id_date = v.id_date
  AND a.utm_campaign_modified = v.utm_campaign_modified
LEFT JOIN fall_back AS fb
	ON fb.id_date = v.id_date
  AND fb.utm_campaign_modified = v.utm_campaign_modified