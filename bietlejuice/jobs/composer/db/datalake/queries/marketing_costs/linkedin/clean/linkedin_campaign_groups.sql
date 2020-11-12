SELECT
    id,
    account_id AS id_account,
    name,
    status,
    total_budget_amount AS total_cost,
    total_budget_currency_code AS total_cost_currency_code,
    run_schedule_start,
    run_schedule_end,
    backfilled,
    account_name,
    acc,
    year,
    month,
    day
FROM datalake_marketing_costs_raw.linkedin_campaign_groups
WHERE
    year={year} and month={month} and day={day}
