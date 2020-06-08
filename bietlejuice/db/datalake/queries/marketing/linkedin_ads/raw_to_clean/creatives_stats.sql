select
    split_part(pivot_value, ':', 4) as id_creative,
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
    text_url_clicks
from datalake_raw.marketing_linkedin_creatives_stats
WHERE dt='{date}' and acc='{account}'