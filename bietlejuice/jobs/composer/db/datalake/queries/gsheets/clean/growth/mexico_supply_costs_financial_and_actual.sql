SELECT
    NULLIF(city_group, '') AS city_group,
    NULLIF(campaign, '') AS campaign,
    NULLIF(business, '') AS business,
    NULLIF(planning_mkt_level1, '') AS planning_mkt_level1,
    NULLIF(planning_mkt_level2, '') AS planning_mkt_level2,
    NULLIF(planning_mkt_level3, '') AS planning_mkt_level3,
    NULLIF(CAST(tier AS INTEGER), '') AS tier,
    NULLIF(FLOAT(budget), '') AS budget,
    NULLIF(FLOAT(budget_mensal), '') AS monthly_budget,
    NULLIF(FLOAT(budget_quarter), '') AS quarterly_budget,
    NULLIF(CAST(month AS INTEGER), '') AS month,
    NULLIF(CAST(year AS INTEGER), '') AS year,
    NULLIF(CAST(halfyear AS INTEGER), '') AS halfyear,
    NULLIF(CAST(quarter AS INTEGER), '') AS quarter,
    NULLIF(DATE(date), '') AS dt_created,
    NULLIF(DATE(week), '') AS dt_week_started
FROM
    datalake_gsheets_raw.mexico_supply_costs_financial_and_actual