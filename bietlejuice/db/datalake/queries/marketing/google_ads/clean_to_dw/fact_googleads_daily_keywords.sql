WITH latest_data as (
    SELECT keywords.keywordid as sk_keyword,
      keywords.account as account_name,
      keywords.campaign as campaign_name,
      keywords.adgroup as adgroup_name,
      keywords.keyword as keyword_name,
      keywords.matchtype as match_type,
      (cast(keywords.cost as FLOAT) / 1000000) as total_cost,
      keywords.clicks as total_clicks,
      to_char(keywords.day::date, 'YYYYMMDD')::int as sk_date,
    RANK() OVER (PARTITION BY keywords.day, keywords.keywordid
                 ORDER BY keywords._sdc_report_datetime DESC)
    FROM datalake_clean.marketing_googleads_keywords keywords
    WHERE keywords.created_dt = '{dt}'
    ORDER BY keywords.day ASC
)
SELECT * FROM latest_data
WHERE rank = 1