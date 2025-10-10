WITH cities AS (
  SELECT 
    DISTINCT LOWER(municipio_clean) AS city_name
  FROM
    datalake_seo_keywords_clusters.ibge_cities
  WHERE
    municipio_clean IS NOT NULL
    AND municipio_clean != ' '
),
keywords AS (
  SELECT
    *
  FROM 
    datalake_google_search_console_classified.gsc_keywords
  WHERE
    domain IN ("imovelweb", "wimoveis", "casamineira")
    AND dt_created BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
),
general_city_level_enrichment AS (
  SELECT
    keyword,
    keyword_clean,
    CASE
      WHEN CONTAINS(c.city_name, ' ') THEN city_name
      WHEN ARRAY_CONTAINS(SPLIT(keyword_clean, ' '), LOWER(c.city_name)) THEN city_name
      WHEN CONTAINS(keyword_clean, 'sao paulo') THEN COALESCE(c.city_name, 'sao paulo')
      WHEN RLIKE(keyword_clean, r'.*(\bsp\b).*') THEN COALESCE(c.city_name, 'sao paulo')
      WHEN RLIKE(keyword_clean, r'.*(\brj\b).*') THEN COALESCE(c.city_name, 'rio de janeiro')
      WHEN CONTAINS(keyword_clean, ' bh') THEN COALESCE(c.city_name, 'belo horizonte')
      WHEN CONTAINS(keyword_clean, ' sjc') THEN COALESCE(c.city_name, 'sao jose dos campos')
      WHEN CONTAINS(keyword_clean, ' santo andre') THEN COALESCE(c.city_name, 'santo andre')
      WHEN CONTAINS(keyword_clean, ' sao caetano') THEN COALESCE(c.city_name, 'sao caetano do sul')
      WHEN CONTAINS(keyword_clean, ' goiania') THEN COALESCE(c.city_name, 'goiania')
      WHEN CONTAINS(keyword_clean, ' nova iguacu') THEN COALESCE(c.city_name, 'nova iguacu')
      WHEN CONTAINS(keyword_clean, ' sao goncalo') THEN COALESCE(c.city_name, 'sao goncalo')
      WHEN CONTAINS(keyword_clean, ' carapicuiba') THEN COALESCE(c.city_name, 'carapicuiba')
      WHEN CONTAINS(keyword_clean, ' sbc') THEN COALESCE(c.city_name, 'sao bernardo do campo')
      WHEN CONTAINS(keyword_clean, ' sbo') THEN COALESCE(c.city_name, 'santa barbara do oeste')
      WHEN CONTAINS(keyword_clean, ' vcp') THEN COALESCE(c.city_name, 'campinas')
      WHEN CONTAINS(keyword_clean, ' vix') THEN COALESCE(c.city_name, 'vitória')
      WHEN CONTAINS(keyword_clean, ' gru') THEN COALESCE(c.city_name, 'guarulhos')
      WHEN CONTAINS(keyword_clean, ' sao bernardo do campo') THEN COALESCE(c.city_name, 'sao bernardo do campo')
      ELSE COALESCE(c.city_name, '')
    END AS match_ibge_city,
    page,
    structure,
    business_context,
    country,
    position,
    impressions,
    clicks,
    ctr,
    site_url,
    posimp,
    device,
    domain,
    is_branded,
    dt_created,
    year,
    month,
    day
  FROM
    keywords AS k
  LEFT JOIN 
    cities AS c
      ON CHARINDEX(LOWER(c.city_name), LOWER(k.keyword_clean)) > 0
  QUALIFY ROW_NUMBER() OVER(
    PARTITION BY dt_created, keyword_clean, page, device
    ORDER BY LENGTH(match_ibge_city) DESC, CHARINDEX(match_ibge_city, keyword_clean)
    DESC
  ) = 1
)
SELECT 
  keyword,
  keyword_clean,
  match_ibge_city,
  page,
  structure,
  business_context,
  site_url,
  device,
  domain,
  country,
  position,
  impressions,
  clicks,
  ctr,
  posimp,
  is_branded,
  CASE
    WHEN match_ibge_city != '' THEN 1
    ELSE 0
  END AS has_mention_to_city,
  dt_created,
  year,
  month,
  day
FROM
  general_city_level_enrichment