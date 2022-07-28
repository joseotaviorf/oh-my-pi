SELECT
    split(pivot_value,'[\:]')[3] AS id_creative,
    card_clicks,
    card_impressions,
    clicks,
    comments,
    company_page_clicks,
    cost_in_local_currency,
    follows,
    impressions,
    likes,
    opens,
    reactions,
    shares,
    sends,
    text_url_clicks,
    acc,
    year,
    month,
    day
FROM datalake_marketing_costs_raw.linkedin_creatives_stats
WHERE
    year={year} and month={month} and day={day}
