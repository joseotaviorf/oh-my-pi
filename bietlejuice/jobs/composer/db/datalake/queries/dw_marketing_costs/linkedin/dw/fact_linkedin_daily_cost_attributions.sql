SELECT
    id_creative AS sk_creative,
    cam.id AS sk_campaign,
    cgr.id AS sk_campaign_group,
    CAST(
      CONCAT(
        string(year),
        lpad(string(month), 2, '0'),
        lpad(string(day), 2, '0')
      )
    AS integer) AS sk_date,
    cost_in_local_currency AS total_cost,
    card_clicks,
    card_impressions,
    clicks,
    comments,
    company_page_clicks,
    follows,
    impressions,
    likes,
    opens,
    reactions,
    shares,
    sends,
    text_url_clicks,
    stats.year,
    stats.month,
    stats.day,
    NOW() AS ts_load
FROM datalake_marketing_costs_clean.linkedin_creatives_stats stats
    JOIN datalake_marketing_costs_clean.linkedin_creatives ctv
        ON ctv.id = stats.id_creative
        AND ctv.acc = stats.acc
        AND ctv.year = stats.year
        AND ctv.month = stats.month
        AND ctv.day = stats.day
    JOIN datalake_marketing_costs_clean.linkedin_campaigns cam
        ON cam.id = ctv.id_campaign
        AND cam.acc = ctv.acc
        AND cam.year = ctv.year
        AND cam.month = ctv.month
        AND cam.day = ctv.day
    JOIN datalake_marketing_costs_clean.linkedin_campaign_groups cgr
        ON cgr.id = cam.id_campaign_group
        AND cgr.acc = cam.acc
        AND cgr.year = cam.year
        AND cgr.month = cam.month
        AND cgr.day = cam.day
