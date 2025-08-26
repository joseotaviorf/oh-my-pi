WITH cities AS (
  SELECT
    DISTINCT LOWER(municipio_clean) as city_name
  FROM
    datalake_seo_keywords_clusters.ibge_cities
  WHERE
    municipio_clean IS NOT NULL
    AND municipio_clean != ' '
),

-- Enrichment of keywords from a IGBE database contains all Brazilian cities.
general_city_level_enrichment AS (
  SELECT
    DISTINCT dt_created,
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
    page,
    google_property,
    branded,
    page_cluster,
    structure,
    page_path,
    state,
    city,
    location_level,
    search_region,
    poi_type,
    filter_count,
    filter_combination,
    position,
    impressions,
    clicks,
    ctr,
    posimp,
    site_url,
    device,
    domain,
    slug,
    subtitle_content,
    is_branded,
    year,
    month,
    day
  FROM
    datalake_google_search_console.gsc_keywords AS kfp
  LEFT JOIN
    cities AS c 
      ON CHARINDEX(LOWER(c.city_name), LOWER(kfp.keyword_clean)) > 0 
  WHERE
    kfp.dt_created BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
  QUALIFY ROW_NUMBER() OVER(
    PARTITION BY dt_created, keyword, page, device
    ORDER BY LENGTH(match_igbe_city) DESC, CHARINDEX(match_igbe_city, keyword) DESC
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
    DISTINCT r.id AS id_region_match_operation_city,
    dt_created,
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
    page,
    google_property,
    branded,
    page_cluster,
    structure,
    page_path,
    state,
    city,
    location_level,
    search_region,
    poi_type,
    filter_count,
    filter_combination,
    position,
    impressions,
    clicks,
    ctr,
    posimp,
    site_url,
    device,
    domain,
    slug,
    subtitle_content,
    is_branded,
    CASE
      WHEN match_igbe_city != '' THEN 1
      ELSE 0
    END AS has_mention_to_location,
    CASE
      WHEN match_igbe_city != '' THEN 1
      ELSE 0
    END AS has_mention_to_city,
    year,
    month,
    day
  FROM
    general_city_level_enrichment AS gcle
  LEFT JOIN
    operation_cities AS r 
      ON CHARINDEX(r.name, gcle.keyword_clean) > 0
      QUALIFY ROW_NUMBER() OVER(
        PARTITION BY dt_created, keyword, page, device
        ORDER BY LENGTH(match_operation_city) DESC, CHARINDEX(match_operation_city, keyword) DESC
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
    DISTINCT id_region_match_operation_city,
    r.id AS id_region_match_operation_neighborhood,
    dt_created,
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
    page,
    google_property,
    branded,
    page_cluster,
    structure,
    page_path,
    state,
    city,
    location_level,
    search_region,
    poi_type,
    filter_count,
    filter_combination,
    position,
    impressions,
    clicks,
    ctr,
    posimp,
    site_url,
    device,
    domain,
    slug,
    subtitle_content,
    is_branded,
    COALESCE(
      gcle.has_mention_to_location,
      CASE
        WHEN match_operation_city != '' THEN 1
        ELSE 0
      END
    ) AS has_mention_to_location,
    COALESCE(
      gcle.has_mention_to_city,
      CASE
        WHEN match_operation_city != '' THEN 1
        ELSE 0
      END
    ) AS has_mention_to_city,
    year,
    month,
    day
  FROM
    operation_city_level_enrichment AS gcle
  LEFT JOIN
    operation_neighborhoodies AS r
      ON CHARINDEX(r.name, gcle.keyword_clean) > 0
      QUALIFY ROW_NUMBER() OVER(
        PARTITION BY dt_created, keyword, page, device
        ORDER BY LENGTH(match_operation_neighborhood) DESC, CHARINDEX(match_operation_neighborhood, keyword) DESC
      ) = 1
)
SELECT
  id_region_match_operation_city,
  id_region_match_operation_neighborhood,
  dt_created,
  keyword,
  keyword_clean,
  match_igbe_city,
  match_operation_city,
  match_operation_neighborhood,
  page,
  google_property,
  branded,
  page_cluster,
  structure,
  page_path,
  state,
  city,
  location_level,
  search_region,
  poi_type,
  filter_count,
  filter_combination,
  position,
  impressions,
  clicks,
  ctr,
  posimp,
  site_url,
  device,
  domain,
  slug,
  subtitle_content,
  is_branded,
  COALESCE(
    has_mention_to_location,
    CASE
      WHEN match_operation_neighborhood != '' THEN 1
      ELSE 0
    END
  ) AS has_mention_to_location,
  has_mention_to_city,
  CASE
    WHEN match_operation_neighborhood != '' THEN 1
    ELSE 0
  END AS has_mention_to_neighborhood,
  year,
  month,
  day
FROM
  operation_neighborhood_level_enrichment