-- CREATE GOOGLE ADS KEYWORD DAILY FACT TABLE
WITH latest AS (
   SELECT keywords.keywordid as sk_keyword,
      keywords.account as account_name,
      keywords.campaign as campaign_name,
      keywords.adgroup as adgroup_name,
      keywords.keyword as keyword_name,
      keywords.matchtype as match_type,
      (cast(keywords.cost as FLOAT) / 1000000) as total_cost,
      keywords.impressions,
      keywords.clicks,
      to_char(keywords.day::date, 'YYYYMMDD')::int as sk_date,
    RANK() OVER (PARTITION BY day, keywords.keywordid
                 ORDER BY _sdc_report_datetime DESC)
    FROM stitch.googleads_keywords_performance_report keywords
    WHERE dt = '{dt}'
    ORDER BY day ASC
)
SELECT * FROM latest
WHERE rank = 1