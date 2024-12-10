WITH 
-------------------------------------------------------------------------------------------
-- This CTE aims to compute the outcome that will serve as the basis for cost allocation --
-------------------------------------------------------------------------------------------
conversion_metrics AS (
  SELECT
    adt.id_date,
    dr.country_code, 
    dr.city_group, 
    LOWER(fdpe.business_context) AS business_context,
    COUNT(DISTINCT CASE WHEN fdpe.event_name = 'USER FIRST ACTIVATION' THEN fdpe.id_prospect END) AS metric
  FROM datalake_demand_flows.prospect_daily_results AS fdpe 
  LEFT JOIN datalake_growth_taxonomy.media_setup AS dms 
    ON fdpe.naming_convention_sufix = dms.naming_convention_sufix 
  LEFT JOIN datalake_region.region AS dr
    ON fdpe.id_region = dr.id
  LEFT JOIN datalake_quintoandar.aux_date AS adt
    ON fdpe.id_event_date = adt.id_date
  WHERE TRUE 
    AND LOWER(fdpe.business_context) = 'rent'
    AND dms.medium = 'Web Display'
    AND dms.source = 'Facebook'
    AND dr.city_group IN ('Brasília', 'Recife', 'Salvador')
  GROUP BY 1,2,3,4
)
-------------------------------------------------------
-- Applying share factor from conversion_metrics CTE --
-------------------------------------------------------
SELECT
	cm.id_date,
	'{id_rule}' AS id_rule,
  'demand' AS funnel_side, 
  cm.country_code,
	cm.city_group,
  'rent' AS business_context, 
  CASE 
    WHEN NULLIF(SUM(SUM(cm.metric)) OVER(PARTITION BY cm.id_date), 0) = 0 THEN 0.33 
    ELSE FLOAT(SUM(cm.metric))/NULLIF(SUM(SUM(cm.metric)) OVER(PARTITION BY cm.id_date), 0) 
  END AS share
FROM 
  conversion_metrics AS cm
GROUP BY 1,2,3,4,5,6