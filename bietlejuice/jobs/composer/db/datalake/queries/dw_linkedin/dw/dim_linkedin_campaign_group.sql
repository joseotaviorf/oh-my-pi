SELECT DISTINCT
    id AS sk_campaign_group,
    id AS id_campaign_group,
    id_account,
    name AS campaign_group_name,
    account_name,
    year,
    month,
    day,
    NOW() AS ts_load
FROM
    datalake_marketing_costs_clean.linkedin_campaign_groups
WHERE
    year = '{year}' AND month = '{month}' AND day = '{day}'