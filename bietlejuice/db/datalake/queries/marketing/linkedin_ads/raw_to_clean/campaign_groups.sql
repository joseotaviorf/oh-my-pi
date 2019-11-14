select
    id,
    name,
    status,
    total_budget_amount as total_cost,
    total_budget_currency_code as total_cost_currency_code,
    run_schedule_start,
    run_schedule_end,
    backfilled,
    account_id as id_account,
    account_name
from datalake_raw.marketing_linkedin_campaign_groups
WHERE dt='{date}' and acc='{account}'