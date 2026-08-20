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
-- The "keyword contains city_name" match is driven by a trigram equi-join (hash
-- key = leading 3 chars) + an exact LOCATE(...) residual, instead of a bare
-- CHARINDEX(...) > 0 join that plans as a BroadcastNestedLoopJoin on EMR. All
-- ibge city_name values are >= 3 chars, so the trigram equi-join is complete.
igbe_city_windows AS (
  SELECT DISTINCT
    keyword_clean,
    SUBSTRING(LOWER(keyword_clean), seq.pos, 3) AS window3
  FROM keywords_grouped
  LATERAL VIEW POSEXPLODE(SEQUENCE(1, GREATEST(LENGTH(keyword_clean) - 2, 0))) seq AS seq_idx, pos
),
igbe_city_matches AS (
  SELECT DISTINCT
    cw.keyword_clean AS keyword_clean,
    c.city_name AS city_name
  FROM igbe_city_windows cw
  JOIN cities c
    ON cw.window3 = SUBSTRING(LOWER(c.city_name), 1, 3)
  WHERE LENGTH(c.city_name) >= 3
    AND LOCATE(LOWER(c.city_name), LOWER(cw.keyword_clean)) > 0
),
general_city_level_candidates AS (
  SELECT
    kg.player,
    kg.keyword,
    kg.keyword_clean,
    CASE
      WHEN CONTAINS(cm.city_name, ' ') THEN cm.city_name
      WHEN ARRAY_CONTAINS(SPLIT(kg.keyword_clean, ' '), LOWER(cm.city_name)) THEN cm.city_name
      WHEN CONTAINS(kg.keyword_clean, 'sao paulo') THEN COALESCE(cm.city_name, 'sao paulo')
      WHEN RLIKE(kg.keyword_clean, r'.*(\bsp\b).*') THEN COALESCE(cm.city_name, 'sao paulo')
      WHEN RLIKE(kg.keyword_clean, r'.*(\brj\b).*') THEN COALESCE(cm.city_name, 'rio de janeiro')
      WHEN CONTAINS(kg.keyword_clean, ' bh') THEN COALESCE(cm.city_name, 'belo horizonte')
      WHEN CONTAINS(kg.keyword_clean, ' sjc') THEN COALESCE(cm.city_name, 'sao jose dos campos')
      WHEN CONTAINS(kg.keyword_clean, ' santo andre') THEN COALESCE(cm.city_name, 'santo andre')
      WHEN CONTAINS(kg.keyword_clean, ' sao caetano') THEN COALESCE(cm.city_name, 'sao caetano do sul')
      WHEN CONTAINS(kg.keyword_clean, ' goiania') THEN COALESCE(cm.city_name, 'goiania')
      WHEN CONTAINS(kg.keyword_clean, ' nova iguacu') THEN COALESCE(cm.city_name, 'nova iguacu')
      WHEN CONTAINS(kg.keyword_clean, ' sao goncalo') THEN COALESCE(cm.city_name, 'sao goncalo')
      WHEN CONTAINS(kg.keyword_clean, ' carapicuiba') THEN COALESCE(cm.city_name, 'carapicuiba')
      WHEN CONTAINS(kg.keyword_clean, ' sbc') THEN COALESCE(cm.city_name, 'sao bernardo do campo')
      WHEN CONTAINS(kg.keyword_clean, ' sbo') THEN COALESCE(cm.city_name, 'santa barbara do oeste')
      WHEN CONTAINS(kg.keyword_clean, ' vcp') THEN COALESCE(cm.city_name, 'campinas')
      WHEN CONTAINS(kg.keyword_clean, ' vix') THEN COALESCE(cm.city_name, 'vitória')
      WHEN CONTAINS(kg.keyword_clean, ' gru') THEN COALESCE(cm.city_name, 'guarulhos')
      WHEN CONTAINS(kg.keyword_clean, ' sao bernardo do campo') THEN COALESCE(cm.city_name, 'sao bernardo do campo')
      ELSE COALESCE(cm.city_name, '')
    END AS match_igbe_city,
    kg.url
  FROM
    keywords_grouped AS kg
  LEFT JOIN
    igbe_city_matches AS cm
      ON kg.keyword_clean = cm.keyword_clean
),
general_city_level_enrichment AS (
  SELECT
    player,
    keyword,
    keyword_clean,
    match_igbe_city,
    url
  FROM (
    SELECT
      player,
      keyword,
      keyword_clean,
      match_igbe_city,
      url,
      ROW_NUMBER() OVER(
        PARTITION BY
          player,
          keyword,
          url
        ORDER BY
          LENGTH(match_igbe_city) DESC,
          LOCATE(match_igbe_city, keyword) DESC
      ) AS rn
    FROM general_city_level_candidates
  ) ranked
  WHERE rn = 1
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
-- Trigram equi-join + LOCATE residual (replaces CHARINDEX containment join).
-- All operation-city names are >= 3 chars, so the trigram key is complete.
opcity_windows AS (
  SELECT DISTINCT
    keyword_clean,
    SUBSTRING(keyword_clean, seq.pos, 3) AS window3
  FROM general_city_level_enrichment
  LATERAL VIEW POSEXPLODE(SEQUENCE(1, GREATEST(LENGTH(keyword_clean) - 2, 0))) seq AS seq_idx, pos
),
opcity_matches AS (
  SELECT DISTINCT
    ow.keyword_clean AS keyword_clean,
    r.id AS id,
    r.name AS name
  FROM opcity_windows ow
  JOIN operation_cities r
    ON ow.window3 = SUBSTRING(r.name, 1, 3)
  WHERE LENGTH(r.name) >= 3
    AND LOCATE(r.name, ow.keyword_clean) > 0
),
operation_city_level_candidates AS (
  SELECT
    om.id AS id_region_match_operation_city,
    gcle.player,
    gcle.keyword,
    gcle.keyword_clean,
    gcle.match_igbe_city,
    CASE
      WHEN CONTAINS(gcle.keyword_clean, om.name) THEN om.name
      WHEN CONTAINS(om.name, ' ') THEN om.name
      WHEN ARRAY_CONTAINS(SPLIT(gcle.keyword_clean, ' '), om.name) THEN om.name
      WHEN CONTAINS(gcle.keyword_clean, 'sao paulo') THEN COALESCE(om.name, 'sao paulo')
      WHEN RLIKE(gcle.keyword_clean, r'.*(\bsp\b).*') THEN COALESCE(om.name, 'sao paulo')
      WHEN RLIKE(gcle.keyword_clean, r'.*(\brj\b).*') THEN COALESCE(om.name, 'rio de janeiro')
      WHEN CONTAINS(gcle.keyword_clean, ' bh') THEN COALESCE(om.name, 'belo horizonte')
      WHEN CONTAINS(gcle.keyword_clean, ' sjc') THEN COALESCE(om.name, 'sao jose dos campos')
      WHEN CONTAINS(gcle.keyword_clean, ' santo andre') THEN COALESCE(om.name, 'santo andre')
      WHEN CONTAINS(gcle.keyword_clean, ' sao caetano') THEN COALESCE(om.name, 'sao caetano do sul')
      WHEN CONTAINS(gcle.keyword_clean, ' goiania') THEN COALESCE(om.name, 'goiania')
      WHEN CONTAINS(gcle.keyword_clean, ' nova iguacu') THEN COALESCE(om.name, 'nova iguacu')
      WHEN CONTAINS(gcle.keyword_clean, ' sao goncalo') THEN COALESCE(om.name, 'sao goncalo')
      WHEN CONTAINS(gcle.keyword_clean, ' carapicuiba') THEN COALESCE(om.name, 'carapicuiba')
      WHEN CONTAINS(gcle.keyword_clean, ' sbc') THEN COALESCE(om.name, 'sao bernardo do campo')
      WHEN CONTAINS(gcle.keyword_clean, ' sbo') THEN COALESCE(om.name, 'santa barbara do oeste')
      WHEN CONTAINS(gcle.keyword_clean, ' vcp') THEN COALESCE(om.name, 'campinas')
      WHEN CONTAINS(gcle.keyword_clean, ' vix') THEN COALESCE(om.name, 'vitória')
      WHEN CONTAINS(gcle.keyword_clean, ' gru') THEN COALESCE(om.name, 'guarulhos')
      WHEN CONTAINS(gcle.keyword_clean, ' sao bernardo do campo') THEN COALESCE(om.name, 'sao bernardo do campo')
      ELSE COALESCE(om.name, '')
    END AS match_operation_city,
    gcle.url,
    CASE
      WHEN gcle.match_igbe_city != '' THEN 1
      ELSE 0
    END AS has_mention_to_location,
    CASE
      WHEN gcle.match_igbe_city != '' THEN 1
      ELSE 0
    END AS has_mention_to_city
  FROM
    general_city_level_enrichment AS gcle
  LEFT JOIN
    opcity_matches AS om
      ON gcle.keyword_clean = om.keyword_clean
),
operation_city_level_enrichment AS (
  SELECT
    id_region_match_operation_city,
    player,
    keyword,
    keyword_clean,
    match_igbe_city,
    match_operation_city,
    url,
    has_mention_to_location,
    has_mention_to_city
  FROM (
    SELECT
      id_region_match_operation_city,
      player,
      keyword,
      keyword_clean,
      match_igbe_city,
      match_operation_city,
      url,
      has_mention_to_location,
      has_mention_to_city,
      ROW_NUMBER() OVER(
        PARTITION BY
          player,
          keyword,
          url
        ORDER BY
          LENGTH(match_operation_city) DESC,
          LOCATE(match_operation_city, keyword) DESC
      ) AS rn
    FROM operation_city_level_candidates
  ) ranked
  WHERE rn = 1
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
-- Trigram equi-join + LOCATE residual (replaces CHARINDEX containment join).
-- A few SubRegiao names are < 3 chars; they can't form a trigram key, so a small
-- validator-exempt CROSS JOIN branch preserves them exactly.
opnbhd_keywords AS (
  SELECT DISTINCT keyword_clean FROM operation_city_level_enrichment
),
opnbhd_windows AS (
  SELECT DISTINCT
    keyword_clean,
    SUBSTRING(keyword_clean, seq.pos, 3) AS window3
  FROM opnbhd_keywords
  LATERAL VIEW POSEXPLODE(SEQUENCE(1, GREATEST(LENGTH(keyword_clean) - 2, 0))) seq AS seq_idx, pos
),
opnbhd_matches AS (
  SELECT DISTINCT
    ow.keyword_clean AS keyword_clean,
    r.id AS id,
    r.name AS name
  FROM opnbhd_windows ow
  JOIN operation_neighborhoodies r
    ON ow.window3 = SUBSTRING(r.name, 1, 3)
  WHERE LENGTH(r.name) >= 3
    AND LOCATE(r.name, ow.keyword_clean) > 0

  UNION ALL

  SELECT DISTINCT
    ok.keyword_clean AS keyword_clean,
    r.id AS id,
    r.name AS name
  FROM opnbhd_keywords ok
  CROSS JOIN operation_neighborhoodies r
  WHERE LENGTH(r.name) < 3
    AND LOCATE(r.name, ok.keyword_clean) > 0
),
operation_neighborhood_level_candidates AS (
  SELECT
    gcle.id_region_match_operation_city,
    om.id AS id_region_match_operation_neighborhood,
    gcle.player,
    gcle.keyword,
    gcle.keyword_clean,
    gcle.match_igbe_city,
    gcle.match_operation_city,
    CASE
      WHEN CONTAINS(om.name, ' ') THEN om.name
      WHEN ARRAY_CONTAINS(SPLIT(gcle.keyword_clean, ' '), LOWER(om.name)) THEN om.name
      WHEN om.name IS NULL THEN ''
      ELSE ''
    END AS match_operation_neighborhood,
    gcle.url,
    COALESCE(
      gcle.has_mention_to_location,
      CASE
        WHEN gcle.match_operation_city != '' THEN 1
        ELSE 0
      END) AS has_mention_to_location,
    COALESCE(
      gcle.has_mention_to_city,
      CASE
        WHEN gcle.match_operation_city != '' THEN 1
        ELSE 0
      END) AS has_mention_to_city
  FROM
    operation_city_level_enrichment AS gcle
  LEFT JOIN
    opnbhd_matches AS om
      ON gcle.keyword_clean = om.keyword_clean
),
operation_neighborhood_level_enrichment AS (
  SELECT
    id_region_match_operation_city,
    id_region_match_operation_neighborhood,
    player,
    keyword,
    keyword_clean,
    match_igbe_city,
    match_operation_city,
    match_operation_neighborhood,
    url,
    has_mention_to_location,
    has_mention_to_city
  FROM (
    SELECT
      id_region_match_operation_city,
      id_region_match_operation_neighborhood,
      player,
      keyword,
      keyword_clean,
      match_igbe_city,
      match_operation_city,
      match_operation_neighborhood,
      url,
      has_mention_to_location,
      has_mention_to_city,
      ROW_NUMBER() OVER(
        PARTITION BY
          player,
          keyword,
          url
        ORDER BY
          LENGTH(match_operation_neighborhood) DESC,
          LOCATE(match_operation_neighborhood, keyword) DESC
      ) AS rn
    FROM operation_neighborhood_level_candidates
  ) ranked
  WHERE rn = 1
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
