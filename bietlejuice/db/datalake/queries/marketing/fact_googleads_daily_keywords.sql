SELECT DISTINCT
  keywords.keywordid as sk_keyword,
  keywords.keyword as keyword_name,
  keywords.matchtype as match_type,
  (cast(keywords.cost as double) / 1000000) as total_cost,
  keywords.impressions,
  keywords.clicks,
  keywords.day
FROM stitch.adwords_keywords_performance_report keywords
WHERE dt = '{}'