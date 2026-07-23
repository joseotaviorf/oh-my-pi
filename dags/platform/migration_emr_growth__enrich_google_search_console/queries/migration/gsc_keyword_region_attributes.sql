WITH cities AS (
  SELECT DISTINCT
    LOWER(municipio_clean) AS city_name
  FROM datalake_seo_keywords_clusters.ibge_cities
  WHERE
    NOT municipio_clean IS NULL AND municipio_clean <> ' '
), general_city_level_enrichment /* Enrichment of keywords from a IGBE database contains all Brazilian cities. */ AS (
  SELECT
    dt_created,
    keyword,
    keyword_clean,
    match_igbe_city,
    city_abbreviation,
    page,
    google_property,
    branded,
    page_cluster,
    structure,
    page_structure,
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
    is_goldenset,
    year,
    month,
    day
  FROM (
    SELECT DISTINCT
      dt_created,
      keyword,
      keyword_clean,
      CASE
        WHEN CONTAINS(c.city_name, ' ')
        THEN city_name
        WHEN ARRAY_CONTAINS(SPLIT(keyword_clean, ' '), LOWER(c.city_name))
        THEN city_name
        WHEN CONTAINS(keyword_clean, 'sao paulo')
        THEN COALESCE(c.city_name, 'sao paulo')
        WHEN keyword_clean RLIKE '.*(\\bsp\\b).*'
        THEN COALESCE(c.city_name, 'sao paulo')
        WHEN keyword_clean RLIKE '.*(\\brj\\b).*'
        THEN COALESCE(c.city_name, 'rio de janeiro')
        WHEN CONTAINS(keyword_clean, ' bh')
        THEN COALESCE(c.city_name, 'belo horizonte')
        WHEN CONTAINS(keyword_clean, ' sjc')
        THEN COALESCE(c.city_name, 'sao jose dos campos')
        WHEN CONTAINS(keyword_clean, ' santo andre')
        THEN COALESCE(c.city_name, 'santo andre')
        WHEN CONTAINS(keyword_clean, ' sao caetano')
        THEN COALESCE(c.city_name, 'sao caetano do sul')
        WHEN CONTAINS(keyword_clean, ' goiania')
        THEN COALESCE(c.city_name, 'goiania')
        WHEN CONTAINS(keyword_clean, ' nova iguacu')
        THEN COALESCE(c.city_name, 'nova iguacu')
        WHEN CONTAINS(keyword_clean, ' sao goncalo')
        THEN COALESCE(c.city_name, 'sao goncalo')
        WHEN CONTAINS(keyword_clean, ' carapicuiba')
        THEN COALESCE(c.city_name, 'carapicuiba')
        WHEN CONTAINS(keyword_clean, ' sbc')
        THEN COALESCE(c.city_name, 'sao bernardo do campo')
        WHEN CONTAINS(keyword_clean, ' sbo')
        THEN COALESCE(c.city_name, 'santa barbara do oeste')
        WHEN CONTAINS(keyword_clean, ' vcp')
        THEN COALESCE(c.city_name, 'campinas')
        WHEN CONTAINS(keyword_clean, ' vix')
        THEN COALESCE(c.city_name, 'vitória')
        WHEN CONTAINS(keyword_clean, ' gru')
        THEN COALESCE(c.city_name, 'guarulhos')
        WHEN CONTAINS(keyword_clean, ' sao bernardo do campo')
        THEN COALESCE(c.city_name, 'sao bernardo do campo')
        ELSE COALESCE(c.city_name, '')
      END AS match_igbe_city,
      CASE
        WHEN page RLIKE 'belo-horizonte'
        THEN 'BH'
        WHEN page RLIKE 'curitiba'
        THEN 'CWB'
        WHEN page RLIKE 'porto-alegre'
        THEN 'POA'
        WHEN page RLIKE 'rio-de-janeiro'
        THEN 'RJ'
        WHEN page RLIKE 'df-brasil|brasilia-df|distrito-federal|/df/'
        THEN 'BSB'
        WHEN page RLIKE '(sao-paulo|guarulhos|santo-andre|sao-bernardo-do-campo|sao-caetano-do-sul)'
        THEN 'RMSP'
        WHEN page RLIKE '(campinas|sorocaba|jundiai|santos|praia-grande|sao-jose-dos-campos|guaruja)'
        THEN 'SP INTERIOR+LITORAL'
        WHEN page RLIKE '(aruja|barueri|biritiba-mirim|caieiras|cajamar|carapicuiba|cotia|diadema|embu|embu-guacu|ferraz-de-vasconcelos|francisco-morato|franco-da-rocha|guararema|itapecerica-da-serra|itapevi|itaquaquecetuba|jandira|juquitiba|mairipora|maua|mogi-das-cruzes|osasco|pirapora-do-bom-jesus|poa|ribeirao-pires|rio-grande-da-serra|salesopolis|santa-isabel|santana-de-parnaiba|sao-lourenco-da-serra|suzano|taboao-da-serra|vargem-grande-paulista)'
        THEN 'RMSP Outros'
        ELSE 'OUTROS'
      END AS city_abbreviation,
      page,
      google_property,
      branded,
      page_cluster,
      structure,
      page_structure,
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
      is_goldenset,
      year,
      month,
      day,
      ROW_NUMBER() OVER (PARTITION BY dt_created, keyword, page, device, site_url, year, month, day ORDER BY LENGTH(
        CASE
          WHEN CONTAINS(c.city_name, ' ')
          THEN city_name
          WHEN ARRAY_CONTAINS(SPLIT(keyword_clean, ' '), LOWER(c.city_name))
          THEN city_name
          WHEN CONTAINS(keyword_clean, 'sao paulo')
          THEN COALESCE(c.city_name, 'sao paulo')
          WHEN keyword_clean RLIKE '.*(\\bsp\\b).*'
          THEN COALESCE(c.city_name, 'sao paulo')
          WHEN keyword_clean RLIKE '.*(\\brj\\b).*'
          THEN COALESCE(c.city_name, 'rio de janeiro')
          WHEN CONTAINS(keyword_clean, ' bh')
          THEN COALESCE(c.city_name, 'belo horizonte')
          WHEN CONTAINS(keyword_clean, ' sjc')
          THEN COALESCE(c.city_name, 'sao jose dos campos')
          WHEN CONTAINS(keyword_clean, ' santo andre')
          THEN COALESCE(c.city_name, 'santo andre')
          WHEN CONTAINS(keyword_clean, ' sao caetano')
          THEN COALESCE(c.city_name, 'sao caetano do sul')
          WHEN CONTAINS(keyword_clean, ' goiania')
          THEN COALESCE(c.city_name, 'goiania')
          WHEN CONTAINS(keyword_clean, ' nova iguacu')
          THEN COALESCE(c.city_name, 'nova iguacu')
          WHEN CONTAINS(keyword_clean, ' sao goncalo')
          THEN COALESCE(c.city_name, 'sao goncalo')
          WHEN CONTAINS(keyword_clean, ' carapicuiba')
          THEN COALESCE(c.city_name, 'carapicuiba')
          WHEN CONTAINS(keyword_clean, ' sbc')
          THEN COALESCE(c.city_name, 'sao bernardo do campo')
          WHEN CONTAINS(keyword_clean, ' sbo')
          THEN COALESCE(c.city_name, 'santa barbara do oeste')
          WHEN CONTAINS(keyword_clean, ' vcp')
          THEN COALESCE(c.city_name, 'campinas')
          WHEN CONTAINS(keyword_clean, ' vix')
          THEN COALESCE(c.city_name, 'vitória')
          WHEN CONTAINS(keyword_clean, ' gru')
          THEN COALESCE(c.city_name, 'guarulhos')
          WHEN CONTAINS(keyword_clean, ' sao bernardo do campo')
          THEN COALESCE(c.city_name, 'sao bernardo do campo')
          ELSE COALESCE(c.city_name, '')
        END
      ) DESC, LOCATE(
        CASE
          WHEN CONTAINS(c.city_name, ' ')
          THEN city_name
          WHEN ARRAY_CONTAINS(SPLIT(keyword_clean, ' '), LOWER(c.city_name))
          THEN city_name
          WHEN CONTAINS(keyword_clean, 'sao paulo')
          THEN COALESCE(c.city_name, 'sao paulo')
          WHEN keyword_clean RLIKE '.*(\\bsp\\b).*'
          THEN COALESCE(c.city_name, 'sao paulo')
          WHEN keyword_clean RLIKE '.*(\\brj\\b).*'
          THEN COALESCE(c.city_name, 'rio de janeiro')
          WHEN CONTAINS(keyword_clean, ' bh')
          THEN COALESCE(c.city_name, 'belo horizonte')
          WHEN CONTAINS(keyword_clean, ' sjc')
          THEN COALESCE(c.city_name, 'sao jose dos campos')
          WHEN CONTAINS(keyword_clean, ' santo andre')
          THEN COALESCE(c.city_name, 'santo andre')
          WHEN CONTAINS(keyword_clean, ' sao caetano')
          THEN COALESCE(c.city_name, 'sao caetano do sul')
          WHEN CONTAINS(keyword_clean, ' goiania')
          THEN COALESCE(c.city_name, 'goiania')
          WHEN CONTAINS(keyword_clean, ' nova iguacu')
          THEN COALESCE(c.city_name, 'nova iguacu')
          WHEN CONTAINS(keyword_clean, ' sao goncalo')
          THEN COALESCE(c.city_name, 'sao goncalo')
          WHEN CONTAINS(keyword_clean, ' carapicuiba')
          THEN COALESCE(c.city_name, 'carapicuiba')
          WHEN CONTAINS(keyword_clean, ' sbc')
          THEN COALESCE(c.city_name, 'sao bernardo do campo')
          WHEN CONTAINS(keyword_clean, ' sbo')
          THEN COALESCE(c.city_name, 'santa barbara do oeste')
          WHEN CONTAINS(keyword_clean, ' vcp')
          THEN COALESCE(c.city_name, 'campinas')
          WHEN CONTAINS(keyword_clean, ' vix')
          THEN COALESCE(c.city_name, 'vitória')
          WHEN CONTAINS(keyword_clean, ' gru')
          THEN COALESCE(c.city_name, 'guarulhos')
          WHEN CONTAINS(keyword_clean, ' sao bernardo do campo')
          THEN COALESCE(c.city_name, 'sao bernardo do campo')
          ELSE COALESCE(c.city_name, '')
        END,
        keyword
      ) DESC) AS _w
    FROM datalake_google_search_console.gsc_keywords AS kfp
    LEFT JOIN cities AS c
      ON LOCATE(LOWER(c.city_name), LOWER(kfp.keyword_clean)) > 0
    WHERE
      kfp.dt_created BETWEEN CAST('{load_start_date}' AS DATE) AND CAST('{load_end_date}' AS DATE)
  ) AS _t
  WHERE
    _w = 1
), operation_cities AS (
  SELECT
    r.id,
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
    ) AS name /* Replaces the UDF SF_SET_ALPHANUMERIC_LOWER */
  FROM datalake_region.region AS r
  WHERE
    r.level = 'Cidade'
), operation_city_level_enrichment /* Enrichment of keywords on city level based on our internal regions dataset. */ /* This dataset comprehends only our operations area. */ AS (
  SELECT
    id_region_match_operation_city,
    dt_created,
    keyword,
    keyword_clean,
    match_igbe_city,
    city_abbreviation,
    match_operation_city,
    page,
    google_property,
    branded,
    page_cluster,
    structure,
    page_structure,
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
    is_goldenset,
    has_mention_to_location,
    has_mention_to_city,
    year,
    month,
    day
  FROM (
    SELECT DISTINCT
      r.id AS id_region_match_operation_city,
      dt_created,
      keyword,
      keyword_clean,
      match_igbe_city,
      city_abbreviation,
      CASE
        WHEN CONTAINS(keyword_clean, r.name)
        THEN r.name
        WHEN CONTAINS(r.name, ' ')
        THEN r.name
        WHEN ARRAY_CONTAINS(SPLIT(keyword_clean, ' '), r.name)
        THEN r.name
        WHEN CONTAINS(keyword_clean, 'sao paulo')
        THEN COALESCE(r.name, 'sao paulo')
        WHEN keyword_clean RLIKE '.*(\\bsp\\b).*'
        THEN COALESCE(r.name, 'sao paulo')
        WHEN keyword_clean RLIKE '.*(\\brj\\b).*'
        THEN COALESCE(r.name, 'rio de janeiro')
        WHEN CONTAINS(keyword_clean, ' bh')
        THEN COALESCE(r.name, 'belo horizonte')
        WHEN CONTAINS(keyword_clean, ' sjc')
        THEN COALESCE(r.name, 'sao jose dos campos')
        WHEN CONTAINS(keyword_clean, ' santo andre')
        THEN COALESCE(r.name, 'santo andre')
        WHEN CONTAINS(keyword_clean, ' sao caetano')
        THEN COALESCE(r.name, 'sao caetano do sul')
        WHEN CONTAINS(keyword_clean, ' goiania')
        THEN COALESCE(r.name, 'goiania')
        WHEN CONTAINS(keyword_clean, ' nova iguacu')
        THEN COALESCE(r.name, 'nova iguacu')
        WHEN CONTAINS(keyword_clean, ' sao goncalo')
        THEN COALESCE(r.name, 'sao goncalo')
        WHEN CONTAINS(keyword_clean, ' carapicuiba')
        THEN COALESCE(r.name, 'carapicuiba')
        WHEN CONTAINS(keyword_clean, ' sbc')
        THEN COALESCE(r.name, 'sao bernardo do campo')
        WHEN CONTAINS(keyword_clean, ' sbo')
        THEN COALESCE(r.name, 'santa barbara do oeste')
        WHEN CONTAINS(keyword_clean, ' vcp')
        THEN COALESCE(r.name, 'campinas')
        WHEN CONTAINS(keyword_clean, ' vix')
        THEN COALESCE(r.name, 'vitória')
        WHEN CONTAINS(keyword_clean, ' gru')
        THEN COALESCE(r.name, 'guarulhos')
        WHEN CONTAINS(keyword_clean, ' sao bernardo do campo')
        THEN COALESCE(r.name, 'sao bernardo do campo')
        ELSE COALESCE(r.name, '')
      END AS match_operation_city,
      page,
      google_property,
      branded,
      page_cluster,
      structure,
      page_structure,
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
      is_goldenset,
      CASE WHEN match_igbe_city <> '' THEN 1 ELSE 0 END AS has_mention_to_location,
      CASE WHEN match_igbe_city <> '' THEN 1 ELSE 0 END AS has_mention_to_city,
      year,
      month,
      day,
      ROW_NUMBER() OVER (PARTITION BY dt_created, keyword, page, device, site_url, year, month, day ORDER BY LENGTH(
        CASE
          WHEN CONTAINS(keyword_clean, r.name)
          THEN r.name
          WHEN CONTAINS(r.name, ' ')
          THEN r.name
          WHEN ARRAY_CONTAINS(SPLIT(keyword_clean, ' '), r.name)
          THEN r.name
          WHEN CONTAINS(keyword_clean, 'sao paulo')
          THEN COALESCE(r.name, 'sao paulo')
          WHEN keyword_clean RLIKE '.*(\\bsp\\b).*'
          THEN COALESCE(r.name, 'sao paulo')
          WHEN keyword_clean RLIKE '.*(\\brj\\b).*'
          THEN COALESCE(r.name, 'rio de janeiro')
          WHEN CONTAINS(keyword_clean, ' bh')
          THEN COALESCE(r.name, 'belo horizonte')
          WHEN CONTAINS(keyword_clean, ' sjc')
          THEN COALESCE(r.name, 'sao jose dos campos')
          WHEN CONTAINS(keyword_clean, ' santo andre')
          THEN COALESCE(r.name, 'santo andre')
          WHEN CONTAINS(keyword_clean, ' sao caetano')
          THEN COALESCE(r.name, 'sao caetano do sul')
          WHEN CONTAINS(keyword_clean, ' goiania')
          THEN COALESCE(r.name, 'goiania')
          WHEN CONTAINS(keyword_clean, ' nova iguacu')
          THEN COALESCE(r.name, 'nova iguacu')
          WHEN CONTAINS(keyword_clean, ' sao goncalo')
          THEN COALESCE(r.name, 'sao goncalo')
          WHEN CONTAINS(keyword_clean, ' carapicuiba')
          THEN COALESCE(r.name, 'carapicuiba')
          WHEN CONTAINS(keyword_clean, ' sbc')
          THEN COALESCE(r.name, 'sao bernardo do campo')
          WHEN CONTAINS(keyword_clean, ' sbo')
          THEN COALESCE(r.name, 'santa barbara do oeste')
          WHEN CONTAINS(keyword_clean, ' vcp')
          THEN COALESCE(r.name, 'campinas')
          WHEN CONTAINS(keyword_clean, ' vix')
          THEN COALESCE(r.name, 'vitória')
          WHEN CONTAINS(keyword_clean, ' gru')
          THEN COALESCE(r.name, 'guarulhos')
          WHEN CONTAINS(keyword_clean, ' sao bernardo do campo')
          THEN COALESCE(r.name, 'sao bernardo do campo')
          ELSE COALESCE(r.name, '')
        END
      ) DESC, LOCATE(
        CASE
          WHEN CONTAINS(keyword_clean, r.name)
          THEN r.name
          WHEN CONTAINS(r.name, ' ')
          THEN r.name
          WHEN ARRAY_CONTAINS(SPLIT(keyword_clean, ' '), r.name)
          THEN r.name
          WHEN CONTAINS(keyword_clean, 'sao paulo')
          THEN COALESCE(r.name, 'sao paulo')
          WHEN keyword_clean RLIKE '.*(\\bsp\\b).*'
          THEN COALESCE(r.name, 'sao paulo')
          WHEN keyword_clean RLIKE '.*(\\brj\\b).*'
          THEN COALESCE(r.name, 'rio de janeiro')
          WHEN CONTAINS(keyword_clean, ' bh')
          THEN COALESCE(r.name, 'belo horizonte')
          WHEN CONTAINS(keyword_clean, ' sjc')
          THEN COALESCE(r.name, 'sao jose dos campos')
          WHEN CONTAINS(keyword_clean, ' santo andre')
          THEN COALESCE(r.name, 'santo andre')
          WHEN CONTAINS(keyword_clean, ' sao caetano')
          THEN COALESCE(r.name, 'sao caetano do sul')
          WHEN CONTAINS(keyword_clean, ' goiania')
          THEN COALESCE(r.name, 'goiania')
          WHEN CONTAINS(keyword_clean, ' nova iguacu')
          THEN COALESCE(r.name, 'nova iguacu')
          WHEN CONTAINS(keyword_clean, ' sao goncalo')
          THEN COALESCE(r.name, 'sao goncalo')
          WHEN CONTAINS(keyword_clean, ' carapicuiba')
          THEN COALESCE(r.name, 'carapicuiba')
          WHEN CONTAINS(keyword_clean, ' sbc')
          THEN COALESCE(r.name, 'sao bernardo do campo')
          WHEN CONTAINS(keyword_clean, ' sbo')
          THEN COALESCE(r.name, 'santa barbara do oeste')
          WHEN CONTAINS(keyword_clean, ' vcp')
          THEN COALESCE(r.name, 'campinas')
          WHEN CONTAINS(keyword_clean, ' vix')
          THEN COALESCE(r.name, 'vitória')
          WHEN CONTAINS(keyword_clean, ' gru')
          THEN COALESCE(r.name, 'guarulhos')
          WHEN CONTAINS(keyword_clean, ' sao bernardo do campo')
          THEN COALESCE(r.name, 'sao bernardo do campo')
          ELSE COALESCE(r.name, '')
        END,
        keyword
      ) DESC) AS _w
    FROM general_city_level_enrichment AS gcle
    LEFT JOIN operation_cities AS r
      ON LOCATE(r.name, gcle.keyword_clean) > 0
  ) AS _t
  WHERE
    _w = 1
), operation_neighborhoodies AS (
  SELECT
    r.id,
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
    ) AS name /* Replaces the UDF SF_SET_ALPHANUMERIC_LOWER */
  FROM datalake_region.region AS r
  WHERE
    r.level = 'SubRegiao'
), operation_neighborhood_level_enrichment /* Enrichment of keywords on neighborhood level based on our internal regions dataset. */ /* This dataset comprehends only our operation area. */ AS (
  SELECT
    id_region_match_operation_city,
    id_region_match_operation_neighborhood,
    dt_created,
    keyword,
    keyword_clean,
    match_igbe_city,
    city_abbreviation,
    match_operation_city,
    match_operation_neighborhood,
    page,
    google_property,
    branded,
    page_cluster,
    structure,
    page_structure,
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
    has_mention_to_location,
    has_mention_to_city,
    is_goldenset,
    year,
    month,
    day
  FROM (
    SELECT DISTINCT
      id_region_match_operation_city,
      r.id AS id_region_match_operation_neighborhood,
      dt_created,
      keyword,
      keyword_clean,
      match_igbe_city,
      city_abbreviation,
      match_operation_city,
      CASE
        WHEN CONTAINS(r.name, ' ')
        THEN r.name
        WHEN ARRAY_CONTAINS(SPLIT(keyword_clean, ' '), LOWER(r.name))
        THEN r.name
        WHEN r.name IS NULL
        THEN ''
        ELSE ''
      END AS match_operation_neighborhood,
      page,
      google_property,
      branded,
      page_cluster,
      structure,
      page_structure,
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
        CASE WHEN match_operation_city <> '' THEN 1 ELSE 0 END
      ) AS has_mention_to_location,
      COALESCE(gcle.has_mention_to_city, CASE WHEN match_operation_city <> '' THEN 1 ELSE 0 END) AS has_mention_to_city,
      is_goldenset,
      year,
      month,
      day,
      ROW_NUMBER() OVER (PARTITION BY dt_created, keyword, page, device, site_url, year, month, day ORDER BY LENGTH(
        CASE
          WHEN CONTAINS(r.name, ' ')
          THEN r.name
          WHEN ARRAY_CONTAINS(SPLIT(keyword_clean, ' '), LOWER(r.name))
          THEN r.name
          WHEN r.name IS NULL
          THEN ''
          ELSE ''
        END
      ) DESC, LOCATE(
        CASE
          WHEN CONTAINS(r.name, ' ')
          THEN r.name
          WHEN ARRAY_CONTAINS(SPLIT(keyword_clean, ' '), LOWER(r.name))
          THEN r.name
          WHEN r.name IS NULL
          THEN ''
          ELSE ''
        END,
        keyword
      ) DESC) AS _w
    FROM operation_city_level_enrichment AS gcle
    LEFT JOIN operation_neighborhoodies AS r
      ON LOCATE(r.name, gcle.keyword_clean) > 0
  ) AS _t
  WHERE
    _w = 1
)
SELECT
  id_region_match_operation_city,
  id_region_match_operation_neighborhood,
  dt_created,
  keyword,
  keyword_clean,
  match_igbe_city,
  city_abbreviation,
  match_operation_city,
  match_operation_neighborhood,
  page,
  google_property,
  branded,
  page_cluster,
  structure,
  page_structure,
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
    CASE WHEN match_operation_neighborhood <> '' THEN 1 ELSE 0 END
  ) AS has_mention_to_location,
  has_mention_to_city,
  CASE WHEN match_operation_neighborhood <> '' THEN 1 ELSE 0 END AS has_mention_to_neighborhood,
  is_goldenset,
  year,
  month,
  day
FROM operation_neighborhood_level_enrichment