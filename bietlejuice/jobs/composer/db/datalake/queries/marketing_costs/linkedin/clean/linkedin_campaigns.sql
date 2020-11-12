SELECT
    id,
    name,
    campaign_group_id AS id_campaign_group,
    account_id AS id_account,
    cost_type,
    daily_budget_amount AS daily_cost,
    daily_budget_currencyCode AS daily_currency_code,
    total_budget_amount AS total_cost,
    total_budget_currencyCode AS total_cost_currency_code,
    unit_cost_amount AS unit_cost,
    unit_cost_currency_code AS unit_cost_currency_code,
    objective_type,
    run_schedule_start,
    run_schedule_end,
    type,
    status,
    locale_country,
    locale_language,
    acc,
    year,
    month,
    day
FROM datalake_marketing_costs_raw.linkedin_campaigns
WHERE
    year={year} and month={month} and day={day}
