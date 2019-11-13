select
	id,
    name,
    campaign_group_id as id_campaign_group,
    account_id as id_account,
    cost_type,
    daily_budget_amount as daily_cost,
    daily_budget_currencyCode as daily_currency_code,
    total_budget_amount as total_cost,
    total_budget_currencyCode as total_cost_currency_code,
    unit_cost_amount as unit_cost,
    unit_cost_currency_code as unit_cost_currency_code,
    objective_type,
    run_schedule_start,
    run_schedule_end,
    type,
    status,
    locale_country,
    locale_language
from datalake_raw.marketing_linkedin_campaigns
WHERE dt='{date}' and acc='{account}'