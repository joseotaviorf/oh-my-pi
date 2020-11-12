SELECT DISTINCT
    id AS sk_campaign,
    id AS id_campaign,
    name AS campaign_name,
    cost_type,
    type,
    locale_country,
    locale_language,
    year,
    month,
    day,
    NOW() AS ts_load
FROM
    datalake_marketing_costs_clean.linkedin_campaigns
WHERE
    year = '{year}' AND month = '{month}' AND day = '{day}'