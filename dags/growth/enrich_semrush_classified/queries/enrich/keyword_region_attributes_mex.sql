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
    datalake_semrush_classified.keywords_from_players
  WHERE
    country = "mex"
    AND year = YEAR(DATE('{load_start_date}'))
    AND month = MONTH(DATE('{load_start_date}'))
),
general_state_level_enrichment AS (
  SELECT
    bd.*,
    CASE
      WHEN CONTAINS(keyword_clean, 'ciudad de mexico') THEN 'ciudad de mexico'
      WHEN RLIKE(keyword_clean, r'.*(\bcdmx\b).*') THEN 'ciudad de mexico'
      ELSE NULL
    END AS match_state
  FROM base_data bd
),
-- The "keyword contains city_clean" match is driven by a trigram equi-join (hash
-- key = leading 3 chars of the lowercased city) + an exact LOCATE(...) residual,
-- instead of a bare CHARINDEX(...) > 0 join that plans as a BroadcastNestedLoopJoin
-- on EMR. All mexico_regions city_clean values are >= 3 chars, so the trigram
-- equi-join is complete on its own.
city_windows AS (
  SELECT DISTINCT
    keyword_clean,
    SUBSTRING(LOWER(keyword_clean), seq.pos, 3) AS window3
  FROM general_state_level_enrichment
  LATERAL VIEW POSEXPLODE(SEQUENCE(1, GREATEST(LENGTH(keyword_clean) - 2, 0))) seq AS seq_idx, pos
),
city_matches AS (
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
      WHEN CONTAINS(cm.city_clean, 'casas') THEN NULL
      WHEN CONTAINS(cm.city_clean, 'xico') THEN NULL
      WHEN CONTAINS(cm.city_clean, ' ') THEN cm.city_clean
      WHEN ARRAY_CONTAINS(SPLIT(gsle.keyword_clean, ' '), LOWER(cm.city_clean)) THEN cm.city_clean
      ELSE COALESCE(cm.city_clean, NULL)
    END AS match_city,
    gsle.*
  FROM general_state_level_enrichment gsle
    LEFT JOIN city_matches cm
      ON gsle.keyword_clean = cm.keyword_clean
),
general_city_level_enrichment AS (
  SELECT *
  FROM (
    SELECT
      gc.*,
      ROW_NUMBER() OVER(
        PARTITION BY dt_report, keyword_clean, url
        ORDER BY LENGTH(match_city) DESC, LOCATE(match_city, keyword_clean) DESC
      ) AS rn_city
    FROM general_city_level_candidates gc
  ) ranked_city
  WHERE rn_city = 1
),
-- Some mexico_regions zone_clean values are < 3 chars (incl. ''), which LOCATE
-- matches everywhere; those can't form a trigram key, so a small validator-exempt
-- CROSS JOIN branch preserves them exactly. Longer zones use the trigram key.
zone_keywords AS (
  SELECT DISTINCT keyword_clean FROM general_city_level_enrichment
),
zone_windows AS (
  SELECT DISTINCT
    keyword_clean,
    SUBSTRING(LOWER(keyword_clean), seq.pos, 3) AS window3
  FROM zone_keywords
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
    zk.keyword_clean AS keyword_clean,
    z.zone_clean AS zone_clean
  FROM zone_keywords zk
  CROSS JOIN zones z
  WHERE LENGTH(z.zone_clean) < 3
    AND LOCATE(LOWER(z.zone_clean), LOWER(zk.keyword_clean)) > 0
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
      WHEN CONTAINS(zm.zone_clean, 'y') THEN ''
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
  SELECT *
  FROM (
    SELECT
      gz.*,
      ROW_NUMBER() OVER(
        PARTITION BY dt_report, keyword_clean, url
        ORDER BY LENGTH(match_zone) DESC, LOCATE(match_zone, keyword_clean) DESC
      ) AS rn_zone
    FROM general_zone_level_candidates gz
  ) ranked_zone
  WHERE rn_zone = 1
)
SELECT
  keyword,
  keyword_clean,
  url,
  COALESCE(match_city, match_state, '') AS match_city,
  match_zone,
  player,
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
  competition,
  number_of_results,
  keyword_difficulty,
  CASE
    WHEN COALESCE(match_city, match_state, '') != '' THEN 1
    ELSE 0
  END AS has_mention_to_city,
  CASE
    WHEN match_zone != '' THEN 1
    ELSE 0
  END AS has_mention_to_zone,
  dt_display,
  dt_report,
  ts_report,
  year,
  month,
  day
FROM
  general_zone_level_enrichment
