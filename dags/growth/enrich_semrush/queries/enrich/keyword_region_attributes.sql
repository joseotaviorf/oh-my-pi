WITH cities AS (
  SELECT DISTINCT
      LOWER(municipio_clean) as city_name
  FROM 
    datalake_seo_keywords_clusters.ibge_cities
  WHERE
    municipio_clean IS NOT NULL AND municipio_clean != ' '
),

keywords AS (
  SELECT
    player,
    keyword,
    keyword_clean,
    url,
    trends,
    position,
    previous_position,
    position_difference,
    keyword_intents,
    position_type,
    serp_features_by_position,
    serp_features_by_keyword,
    search_volume,
    cpc,
    traffic,
    share_of_traffic,
    traffic_cost_percentage,
    competition,
    number_of_results,
    keyword_difficulty,
    city_abbreviation,
    is_goldenset,
    dt_display,
    dt_display AS dt_report,
    ts_report,
    year,
    month,
    day
  FROM
    datalake_semrush.keywords_from_players AS kfp
  WHERE
    kfp.year = YEAR(DATE('{load_start_date}'))
    AND kfp.month = MONTH(DATE('{load_start_date}'))
),

keywords_grouped AS (
  SELECT
    player,
    keyword,
    keyword_clean,
    url
  FROM
    keywords AS kfp
  GROUP BY player, keyword, keyword_clean, url
),

-- Enrichment of keywords from a IGBE database contains all Brazilian cities.
general_city_level_enrichment AS (
  SELECT
    player,
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
    END AS match_igbe_city,
    url
  FROM
    keywords_grouped AS kg
  LEFT JOIN 
    cities AS c 
      ON CHARINDEX(LOWER(c.city_name), LOWER(kg.keyword_clean)) > 0
  QUALIFY
    ROW_NUMBER() OVER(
      PARTITION BY 
        player,
        keyword,
        url
      ORDER BY 
        LENGTH(match_igbe_city) DESC, 
        CHARINDEX(match_igbe_city, keyword) DESC
        ) = 1
),

operation_cities AS (
  SELECT
    r.id,
    -- Replaces the UDF SF_SET_ALPHANUMERIC_LOWER
    LOWER(
      REGEXP_REPLACE(
        TRANSLATE(
          r.name,
          'áàãâäéèêëíìîïóòõôöúùûüçÁÀÃÂÄÉÈÊËÍÌÎÏÓÒÕÔÖÚÙÛÜÇ',
          'aaaaaeeeeiiiiooooouuuucAAAAAEEEEIIIIOOOOOUUUUC'
        ),
        '[^a-zA-Z0-9 ]',
        ''
      )
    ) AS name
  FROM 
    datalake_region.region AS r
  WHERE 
    r.level = 'Cidade'
),

-- Enrichment of keywords on city level based on our internal regions dataset. 
-- This dataset comprehends only our operations area.
operation_city_level_enrichment AS (
  SELECT
    r.id AS id_region_match_operation_city,
    player,
    keyword,
    keyword_clean,
    match_igbe_city,
    CASE
      WHEN CONTAINS(keyword_clean, r.name) THEN r.name
      WHEN CONTAINS(r.name, ' ') THEN r.name
      WHEN ARRAY_CONTAINS(SPLIT(keyword_clean, ' '), r.name) THEN r.name
      WHEN CONTAINS(keyword_clean, 'sao paulo') THEN COALESCE(r.name, 'sao paulo')
      WHEN RLIKE(keyword_clean, r'.*(\bsp\b).*') THEN COALESCE(r.name, 'sao paulo')
      WHEN RLIKE(keyword_clean, r'.*(\brj\b).*') THEN COALESCE(r.name, 'rio de janeiro')
      WHEN CONTAINS(keyword_clean, ' bh') THEN COALESCE(r.name, 'belo horizonte')
      WHEN CONTAINS(keyword_clean, ' sjc') THEN COALESCE(r.name, 'sao jose dos campos')
      WHEN CONTAINS(keyword_clean, ' santo andre') THEN COALESCE(r.name, 'santo andre')
      WHEN CONTAINS(keyword_clean, ' sao caetano') THEN COALESCE(r.name, 'sao caetano do sul')
      WHEN CONTAINS(keyword_clean, ' goiania') THEN COALESCE(r.name, 'goiania')
      WHEN CONTAINS(keyword_clean, ' nova iguacu') THEN COALESCE(r.name, 'nova iguacu')
      WHEN CONTAINS(keyword_clean, ' sao goncalo') THEN COALESCE(r.name, 'sao goncalo')
      WHEN CONTAINS(keyword_clean, ' carapicuiba') THEN COALESCE(r.name, 'carapicuiba')
      WHEN CONTAINS(keyword_clean, ' sbc') THEN COALESCE(r.name, 'sao bernardo do campo')
      WHEN CONTAINS(keyword_clean, ' sbo') THEN COALESCE(r.name, 'santa barbara do oeste')
      WHEN CONTAINS(keyword_clean, ' vcp') THEN COALESCE(r.name, 'campinas')
      WHEN CONTAINS(keyword_clean, ' vix') THEN COALESCE(r.name, 'vitória')
      WHEN CONTAINS(keyword_clean, ' gru') THEN COALESCE(r.name, 'guarulhos')
      WHEN CONTAINS(keyword_clean, ' sao bernardo do campo') THEN COALESCE(r.name, 'sao bernardo do campo')
      ELSE COALESCE(r.name, '')
    END AS match_operation_city,
    url,
    CASE
      WHEN match_igbe_city != '' THEN 1
      ELSE 0
    END AS has_mention_to_location,
    CASE
      WHEN match_igbe_city != '' THEN 1
      ELSE 0
    END AS has_mention_to_city
  FROM
    general_city_level_enrichment AS gcle
  LEFT JOIN 
    operation_cities AS r
      ON CHARINDEX(r.name, gcle.keyword_clean) > 0
  QUALIFY
    ROW_NUMBER() OVER(
      PARTITION BY 
        player,
        keyword,
        url
      ORDER BY 
        LENGTH(match_operation_city) DESC, 
        CHARINDEX(match_operation_city, keyword) DESC
        ) = 1
),

operation_neighborhoodies AS (
  SELECT
    r.id,
    -- Replaces the UDF SF_SET_ALPHANUMERIC_LOWER
    LOWER(
      REGEXP_REPLACE(
        TRANSLATE(
          r.name,
          'áàãâäéèêëíìîïóòõôöúùûüçÁÀÃÂÄÉÈÊËÍÌÎÏÓÒÕÔÖÚÙÛÜÇ',
          'aaaaaeeeeiiiiooooouuuucAAAAAEEEEIIIIOOOOOUUUUC'
        ),
        '[^a-zA-Z0-9 ]',
        ''
      )
    ) AS name
  FROM 
    datalake_region.region AS r
  WHERE 
    r.level = 'SubRegiao'
),

-- Enrichment of keywords on neighborhood level based on our internal regions dataset. 
-- This dataset comprehends only our operation area.
operation_neighborhood_level_enrichment AS (
  SELECT
    id_region_match_operation_city,
    r.id AS id_region_match_operation_neighborhood,
    player,
    keyword,
    keyword_clean,
    match_igbe_city,
    match_operation_city,
    CASE
      WHEN CONTAINS(r.name, ' ') THEN r.name
      WHEN ARRAY_CONTAINS(SPLIT(keyword_clean, ' '), LOWER(r.name)) THEN r.name
      WHEN r.name IS NULL THEN ''
      ELSE ''
    END AS match_operation_neighborhood,
    url,
    COALESCE(
      gcle.has_mention_to_location,
      CASE
        WHEN match_operation_city != '' THEN 1
        ELSE 0
      END) AS has_mention_to_location,
    COALESCE(
      gcle.has_mention_to_city,
      CASE
        WHEN match_operation_city != '' THEN 1
        ELSE 0
      END) AS has_mention_to_city
  FROM
    operation_city_level_enrichment AS gcle
  LEFT JOIN 
    operation_neighborhoodies AS r
      ON CHARINDEX(r.name, gcle.keyword_clean) > 0
  QUALIFY
    ROW_NUMBER() OVER(
      PARTITION BY 
        player,
        keyword,
        url
      ORDER BY 
        LENGTH(match_operation_neighborhood) DESC, 
        CHARINDEX(match_operation_neighborhood, keyword) DESC
        ) = 1
)

SELECT
  id_region_match_operation_city,
  id_region_match_operation_neighborhood,
  k.player,
  k.keyword,
  k.keyword_clean,
  match_igbe_city,
  match_operation_city,
  match_operation_neighborhood,
  k.url,
  trends,
  position,
  previous_position,
  position_difference,
  keyword_intents,
  position_type,
  serp_features_by_position,
  serp_features_by_keyword,
  search_volume,
  cpc,
  traffic,
  share_of_traffic,
  traffic_cost_percentage,
  competition,
  number_of_results,
  keyword_difficulty,
  city_abbreviation,
  is_goldenset,
  COALESCE(
    has_mention_to_location,
    CASE
      WHEN match_operation_neighborhood != '' THEN 1
      ELSE 0
    END) AS has_mention_to_location,
  has_mention_to_city,
  CASE
    WHEN match_operation_neighborhood != '' THEN 1
    ELSE 0
  END AS has_mention_to_neighborhood,
  dt_display,
  dt_display AS dt_report,
  ts_report,
  year,
  month,
  day
FROM
  keywords AS k
LEFT JOIN 
  operation_neighborhood_level_enrichment AS onle
    ON
      k.keyword = onle.keyword
      AND k.player = onle.player
      AND k.url = onle.url
