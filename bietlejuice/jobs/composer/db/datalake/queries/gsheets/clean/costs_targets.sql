SELECT
  business,
  campaign,
  city_group,
  planning_mkt_level1,
  planning_mkt_level2,
  planning_mkt_level3,
  tier,
  budget_mensal AS monthly_budget,
  budget_quarter AS quarterly_budget,
  date AS dt_created,
  year,
  halfyear,
  quarter,
  month,
  week 
FROM
  datalake_gsheets_raw.costs_targets
