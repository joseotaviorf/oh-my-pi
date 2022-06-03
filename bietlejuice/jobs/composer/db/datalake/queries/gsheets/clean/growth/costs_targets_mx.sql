SELECT
  business,
  campaign,
  city_group,
  planning_mkt_level1,
  planning_mkt_level2,
  planning_mkt_level3,
  CAST(tier AS INTEGER) AS tier,
  FLOAT(budget_mensal) AS monthly_budget,
  FLOAT(budget_quarter) AS quarterly_budget,
  CAST(year AS INTEGER) AS year,
  CAST(halfyear AS INTEGER) AS halfyear,
  CAST(quarter AS INTEGER) AS quarter,
  CAST(month AS INTEGER) AS month,
  DATE(date) AS dt_created,
  DATE(week) AS dt_week
FROM
  datalake_gsheets_raw.costs_targets_mx