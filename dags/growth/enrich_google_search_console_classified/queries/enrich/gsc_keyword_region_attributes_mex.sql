WITH cities AS (
  SELECT 
    DISTINCT(city),
    city_clean
  FROM 
    datalake_gsheets_clean.mexico_regions
  WHERE 
    city IS NOT NULL
),
zones AS (
  SELECT 
    DISTINCT(zone), 
    zone_clean
  FROM 
    datalake_gsheets_clean.mexico_regions
  WHERE
    zone IS NOT NULL
),
base_data AS (
  SELECT 
    * 
  FROM 
    datalake_google_search_console_classified.gsc_keywords
  WHERE 
    domain IN ("inmuebles24", "vivanuncios")
    AND dt_created BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
),
unique_keywords AS (
  SELECT
    DISTINCT(keyword_clean) AS keyword_clean
  FROM
    base_data
),
general_state_level_enrichment AS (
  SELECT 
    uk.keyword_clean,
    CASE
      WHEN CONTAINS(keyword_clean, 'ciudad de mexico') THEN 'ciudad de mexico'
      WHEN RLIKE(keyword_clean, r'.*(\bcdmx\b).*') THEN 'ciudad de mexico'
      ELSE NULL
    END AS match_state
  FROM unique_keywords uk
),
general_city_level_enrichment AS (
  SELECT 
    CASE
      WHEN RLIKE(keyword_clean, r'.*(\bgdl\b).*') THEN COALESCE(c.city_clean, 'guadalajara')
      WHEN RLIKE(keyword_clean, r'.*(\bmty\b).*') THEN COALESCE(c.city_clean, 'monterrey')
      WHEN RLIKE(keyword_clean, r'.*(\btj\b).*') THEN COALESCE(c.city_clean, 'tijuana')
      WHEN RLIKE(keyword_clean, r'.*(\bqro\b).*') THEN COALESCE(c.city_clean, 'queretaro')
      WHEN RLIKE(keyword_clean, r'.*(\bslp\b).*') THEN COALESCE(c.city_clean, 'san luis potosi')
      WHEN RLIKE(keyword_clean, r'.*(\bgam\b).*') THEN COALESCE(c.city_clean, 'gustavo a madero')
      WHEN CONTAINS(c.city_clean, 'casas') THEN null
      WHEN CONTAINS(c.city_clean, 'xico') THEN null
      WHEN CONTAINS(c.city_clean, ' ') THEN city_clean
      WHEN ARRAY_CONTAINS(SPLIT(keyword_clean, ' '), LOWER(c.city_clean)) THEN city_clean
      ELSE COALESCE(c.city_clean, null)
    END AS match_city,
    gsle.*
  FROM general_state_level_enrichment gsle
    LEFT JOIN cities c
      ON CHARINDEX(LOWER(c.city_clean), LOWER(gsle.keyword_clean)) > 0
  QUALIFY ROW_NUMBER() OVER(
    PARTITION BY keyword_clean
    ORDER BY LENGTH(match_city) DESC, CHARINDEX(match_city, keyword_clean)
    DESC
  ) = 1
),
general_zone_level_enrichment AS (
  SELECT 
    CASE
      WHEN CONTAINS(z.zone_clean, 'i') THEN ''
      WHEN CONTAINS(z.zone_clean, 'asa') THEN ''
      WHEN CONTAINS(z.zone_clean, 'mexico') THEN ''
      WHEN CONTAINS(z.zone_clean, 'de mexico') THEN ''
      WHEN CONTAINS(z.zone_clean, 'cu') THEN ''
      WHEN CONTAINS(z.zone_clean, 'raices') THEN ''
      WHEN CONTAINS(z.zone_clean, 'residencial') THEN ''
      WHEN CONTAINS(z.zone_clean, ' ') THEN zone_clean
      WHEN ARRAY_CONTAINS(SPLIT(keyword_clean, ' '), LOWER(z.zone_clean)) THEN zone_clean
      ELSE COALESCE(z.zone_clean, '')
    END AS match_zone,
    gcle.*
  FROM general_city_level_enrichment gcle
    LEFT JOIN zones z
      ON CHARINDEX(LOWER(z.zone_clean), LOWER(gcle.keyword_clean)) > 0
  QUALIFY ROW_NUMBER() OVER(
    PARTITION BY keyword_clean
    ORDER BY LENGTH(match_zone) DESC, CHARINDEX(match_zone, keyword_clean)
    DESC
  ) = 1
)
SELECT
  bd.keyword,
  gzle.keyword_clean,
  COALESCE(gzle.match_city, gzle.match_state, '') AS match_city,
  gzle.match_zone,
  bd.page,
  bd.structure,
  bd.business_context,
  bd.site_url,
  bd.device,
  bd.domain,
  bd.country,
  bd.position,
  bd.impressions,
  bd.clicks,
  bd.ctr,
  bd.posimp,
  bd.is_branded,
  CASE
    WHEN COALESCE(gzle.match_city, gzle.match_state, '') != '' THEN 1
    ELSE 0
  END AS has_mention_to_city,
  CASE
    WHEN gzle.match_zone != '' THEN 1
    ELSE 0
  END AS has_mention_to_zone,
  bd.dt_created,
  bd.year,
  bd.month,
  bd.day
FROM
  base_data bd
LEFT JOIN
  general_zone_level_enrichment gzle
    ON bd.keyword_clean = gzle.keyword_clean
