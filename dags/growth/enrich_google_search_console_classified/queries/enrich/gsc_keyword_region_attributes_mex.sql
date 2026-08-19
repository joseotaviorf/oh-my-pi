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
-- Drive the "keyword contains city_clean" match through a trigram equi-join
-- (hash key) + LOCATE residual instead of a bare LOCATE(...) > 0 join, which
-- plans as a BroadcastNestedLoopJoin on EMR. Result set is identical.
city_windows AS (
  SELECT DISTINCT
    keyword_clean,
    SUBSTRING(LOWER(keyword_clean), seq.pos, 3) AS window3
  FROM general_state_level_enrichment
  LATERAL VIEW POSEXPLODE(SEQUENCE(1, GREATEST(LENGTH(keyword_clean) - 2, 0))) seq AS seq_idx, pos
),
city_matches AS (
  -- Every city_clean is >= 3 chars, so the trigram equi-join is complete.
  SELECT DISTINCT
    cw.keyword_clean AS keyword_clean,
    c.city_clean AS city_clean
  FROM city_windows cw
  JOIN cities c
    ON cw.window3 = SUBSTRING(LOWER(c.city_clean), 1, 3)
  WHERE LENGTH(c.city_clean) >= 3
    AND LOCATE(LOWER(c.city_clean), LOWER(cw.keyword_clean)) > 0
),
general_city_level_candidates AS (
  SELECT
    CASE
      WHEN RLIKE(gsle.keyword_clean, r'.*(\bgdl\b).*') THEN COALESCE(cm.city_clean, 'guadalajara')
      WHEN RLIKE(gsle.keyword_clean, r'.*(\bmty\b).*') THEN COALESCE(cm.city_clean, 'monterrey')
      WHEN RLIKE(gsle.keyword_clean, r'.*(\btj\b).*') THEN COALESCE(cm.city_clean, 'tijuana')
      WHEN RLIKE(gsle.keyword_clean, r'.*(\bqro\b).*') THEN COALESCE(cm.city_clean, 'queretaro')
      WHEN RLIKE(gsle.keyword_clean, r'.*(\bslp\b).*') THEN COALESCE(cm.city_clean, 'san luis potosi')
      WHEN RLIKE(gsle.keyword_clean, r'.*(\bgam\b).*') THEN COALESCE(cm.city_clean, 'gustavo a madero')
      WHEN CONTAINS(cm.city_clean, 'casas') THEN null
      WHEN CONTAINS(cm.city_clean, 'xico') THEN null
      WHEN CONTAINS(cm.city_clean, ' ') THEN cm.city_clean
      WHEN ARRAY_CONTAINS(SPLIT(gsle.keyword_clean, ' '), LOWER(cm.city_clean)) THEN cm.city_clean
      ELSE COALESCE(cm.city_clean, null)
    END AS match_city,
    gsle.*
  FROM general_state_level_enrichment gsle
    LEFT JOIN city_matches cm
      ON gsle.keyword_clean = cm.keyword_clean
),
general_city_level_enrichment AS (
  SELECT
    match_city,
    keyword_clean,
    match_state
  FROM (
    SELECT
      match_city,
      keyword_clean,
      match_state,
      ROW_NUMBER() OVER(
        PARTITION BY keyword_clean
        ORDER BY LENGTH(match_city) DESC, LOCATE(match_city, keyword_clean) DESC
      ) AS rn
    FROM
      general_city_level_candidates
  ) ranked
  WHERE
    rn = 1
),
-- Same trigram equi-join + LOCATE residual as the city match. Zone_clean has a
-- few short/empty values (< 3 chars, incl. '' which LOCATE matches everywhere),
-- handled by a validator-exempt CROSS JOIN branch so results stay identical.
zone_windows AS (
  SELECT DISTINCT
    keyword_clean,
    SUBSTRING(LOWER(keyword_clean), seq.pos, 3) AS window3
  FROM general_city_level_enrichment
  LATERAL VIEW POSEXPLODE(SEQUENCE(1, GREATEST(LENGTH(keyword_clean) - 2, 0))) seq AS seq_idx, pos
),
zone_matches AS (
  SELECT DISTINCT
    zw.keyword_clean AS keyword_clean,
    z.zone_clean AS zone_clean
  FROM zone_windows zw
  JOIN zones z
    ON zw.window3 = SUBSTRING(LOWER(z.zone_clean), 1, 3)
  WHERE LENGTH(z.zone_clean) >= 3
    AND LOCATE(LOWER(z.zone_clean), LOWER(zw.keyword_clean)) > 0

  UNION ALL

  SELECT DISTINCT
    gcle.keyword_clean AS keyword_clean,
    z.zone_clean AS zone_clean
  FROM general_city_level_enrichment gcle
  CROSS JOIN zones z
  WHERE LENGTH(z.zone_clean) < 3
    AND LOCATE(LOWER(z.zone_clean), LOWER(gcle.keyword_clean)) > 0
),
general_zone_level_candidates AS (
  SELECT
    CASE
      WHEN CONTAINS(zm.zone_clean, 'i') THEN ''
      WHEN CONTAINS(zm.zone_clean, 'asa') THEN ''
      WHEN CONTAINS(zm.zone_clean, 'mexico') THEN ''
      WHEN CONTAINS(zm.zone_clean, 'de mexico') THEN ''
      WHEN CONTAINS(zm.zone_clean, 'cu') THEN ''
      WHEN CONTAINS(zm.zone_clean, 'raices') THEN ''
      WHEN CONTAINS(zm.zone_clean, 'residencial') THEN ''
      WHEN CONTAINS(zm.zone_clean, ' ') THEN zm.zone_clean
      WHEN ARRAY_CONTAINS(SPLIT(gcle.keyword_clean, ' '), LOWER(zm.zone_clean)) THEN zm.zone_clean
      ELSE COALESCE(zm.zone_clean, '')
    END AS match_zone,
    gcle.*
  FROM general_city_level_enrichment gcle
    LEFT JOIN zone_matches zm
      ON gcle.keyword_clean = zm.keyword_clean
),
general_zone_level_enrichment AS (
  SELECT
    match_zone,
    match_city,
    keyword_clean,
    match_state
  FROM (
    SELECT
      match_zone,
      match_city,
      keyword_clean,
      match_state,
      ROW_NUMBER() OVER(
        PARTITION BY keyword_clean
        ORDER BY LENGTH(match_zone) DESC, LOCATE(match_zone, keyword_clean) DESC
      ) AS rn
    FROM
      general_zone_level_candidates
  ) ranked
  WHERE
    rn = 1
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
