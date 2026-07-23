WITH substructures AS (
  SELECT
    *,
    CASE
      WHEN structure = "Transactional" AND page LIKE "%br/logradouro/%" THEN "Logradouro"
      WHEN structure = "Transactional" AND page LIKE "%br/ponto-de-interesse/%" THEN "Ponto de Interesse"
      WHEN structure = "Condominio" THEN "Condominio"
      WHEN structure = "Inmobiliaria" THEN "Imobiliaria"
      WHEN page LIKE "casamineira.com.br/imovel/%" THEN "Listing"
      WHEN page LIKE "br/propriedades/%" THEN "Listing"
      WHEN structure = "Transactional" THEN "Other Transactional"
      ELSE "N/A"
    END AS substructure
  FROM
    datalake_google_search_console_classified.gsc_keywords
  WHERE
    domain IN ("imovelweb", "wimoveis", "casamineira")
    AND dt_created BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
),
casamineira_region_patterns AS (
  SELECT
    *,
    CASE 
      WHEN CONTAINS(page, "_ac/") OR ENDSWITH(page, "_ac") OR ENDSWITH(page, "_ac.html") OR ENDSWITH(page, "/ac") THEN "Acre"
      WHEN CONTAINS(page, "_al/") OR ENDSWITH(page, "_al") OR ENDSWITH(page, "_al.html") OR ENDSWITH(page, "/al") THEN "Alagoas"
      WHEN CONTAINS(page, "_am/") OR ENDSWITH(page, "_am") OR ENDSWITH(page, "_am.html") OR ENDSWITH(page, "/am") THEN "Amazonas"
      WHEN CONTAINS(page, "_ap/") OR ENDSWITH(page, "_ap") OR ENDSWITH(page, "_ap.html") OR ENDSWITH(page, "/ap") THEN "Amapá"
      WHEN CONTAINS(page, "_ba/") OR ENDSWITH(page, "_ba") OR ENDSWITH(page, "_ba.html") OR ENDSWITH(page, "/ba") THEN "Bahia"
      WHEN CONTAINS(page, "_ce/") OR ENDSWITH(page, "_ce") OR ENDSWITH(page, "_ce.html") OR ENDSWITH(page, "/ce") THEN "Ceará"
      WHEN CONTAINS(page, "_df/") OR ENDSWITH(page, "_df") OR ENDSWITH(page, "_df.html") OR ENDSWITH(page, "/df") THEN "Distrito Federal"
      WHEN CONTAINS(page, "_es/") OR ENDSWITH(page, "_es") OR ENDSWITH(page, "_es.html") OR ENDSWITH(page, "/es") THEN "Espírito Santo"
      WHEN CONTAINS(page, "_go/") OR ENDSWITH(page, "_go") OR ENDSWITH(page, "_go.html") OR ENDSWITH(page, "/go") THEN "Goiás"
      WHEN CONTAINS(page, "_ma/") OR ENDSWITH(page, "_ma") OR ENDSWITH(page, "_ma.html") OR ENDSWITH(page, "/ma") THEN "Maranhão"
      WHEN CONTAINS(page, "_mt/") OR ENDSWITH(page, "_mt") OR ENDSWITH(page, "_mt.html") OR ENDSWITH(page, "/mt") THEN "Mato Grosso"
      WHEN CONTAINS(page, "_ms/") OR ENDSWITH(page, "_ms") OR ENDSWITH(page, "_ms.html") OR ENDSWITH(page, "/ms") THEN "Mato Grosso Do Sul"
      WHEN CONTAINS(page, "_mg/") OR ENDSWITH(page, "_mg") OR ENDSWITH(page, "_mg.html") OR ENDSWITH(page, "/mg") THEN "Minas Gerais"
      WHEN CONTAINS(page, "_pa/") OR ENDSWITH(page, "_pa") OR ENDSWITH(page, "_pa.html") OR ENDSWITH(page, "/pa") THEN "Pará"
      WHEN CONTAINS(page, "_pb/") OR ENDSWITH(page, "_pb") OR ENDSWITH(page, "_pb.html") OR ENDSWITH(page, "/pb") THEN "Paraíba"
      WHEN CONTAINS(page, "_pe/") OR ENDSWITH(page, "_pe") OR ENDSWITH(page, "_pe.html") OR ENDSWITH(page, "/pe") THEN "Pernambuco"
      WHEN CONTAINS(page, "_pi/") OR ENDSWITH(page, "_pi") OR ENDSWITH(page, "_pi.html") OR ENDSWITH(page, "/pi") THEN "Piauí"
      WHEN CONTAINS(page, "_pr/") OR ENDSWITH(page, "_pr") OR ENDSWITH(page, "_pr.html") OR ENDSWITH(page, "/pr") THEN "Paraná"
      WHEN CONTAINS(page, "_rj/") OR ENDSWITH(page, "_rj") OR ENDSWITH(page, "_rj.html") OR ENDSWITH(page, "/rj") THEN "Rio De Janeiro"
      WHEN CONTAINS(page, "_rn/") OR ENDSWITH(page, "_rn") OR ENDSWITH(page, "_rn.html") OR ENDSWITH(page, "/rn") THEN "Rio Grande Do Norte"
      WHEN CONTAINS(page, "_ro/") OR ENDSWITH(page, "_ro") OR ENDSWITH(page, "_ro.html") OR ENDSWITH(page, "/ro") THEN "Rondônia"
      WHEN CONTAINS(page, "_rr/") OR ENDSWITH(page, "_rr") OR ENDSWITH(page, "_rr.html") OR ENDSWITH(page, "/rr") THEN "Roraima"
      WHEN CONTAINS(page, "_rs/") OR ENDSWITH(page, "_rs") OR ENDSWITH(page, "_rs.html") OR ENDSWITH(page, "/rs") THEN "Rio Grande Do Sul"
      WHEN CONTAINS(page, "_sc/") OR ENDSWITH(page, "_sc") OR ENDSWITH(page, "_sc.html") OR ENDSWITH(page, "/sc") THEN "Santa Catarina"
      WHEN CONTAINS(page, "_se/") OR ENDSWITH(page, "_se") OR ENDSWITH(page, "_se.html") OR ENDSWITH(page, "/se") THEN "Sergipe"
      WHEN CONTAINS(page, "_sp/") OR ENDSWITH(page, "_sp") OR ENDSWITH(page, "_sp.html") OR ENDSWITH(page, "/sp") THEN "São Paulo"
      WHEN CONTAINS(page, "_to/") OR ENDSWITH(page, "_to") OR ENDSWITH(page, "_to.html") OR ENDSWITH(page, "/to") THEN "Tocantins"
      WHEN CONTAINS(page, "_op/") OR ENDSWITH(page, "_op") OR ENDSWITH(page, "_op.html") OR ENDSWITH(page, "/op") THEN "Outros Paises"
    END AS page_state
  FROM
    substructures
  WHERE 
    (
      domain = "casamineira"
      AND substructure IN ("Logradouro", "Ponto de Interesse", "Condominio", "Imobiliaria", "Other Transactional")
    ) OR (
      domain = "imovelweb"
      AND substructure IN ("Logradouro", "Ponto de Interesse", "Condominio")
    )
),
casamineira_region_patterns_group AS (
  SELECT
    DISTINCT(page) AS page
  FROM
    casamineira_region_patterns
),
wimoveis_region_patterns AS (
  SELECT
    *,
    CASE
      WHEN CONTAINS(page, "/ac/") OR ENDSWITH(page, "/ac") THEN "Acre"
      WHEN CONTAINS(page, "/al/") OR ENDSWITH(page, "/al") THEN "Alagoas"
      WHEN CONTAINS(page, "/am/") OR ENDSWITH(page, "/am") THEN "Amazonas"
      WHEN CONTAINS(page, "/ap/") OR ENDSWITH(page, "/ap") THEN "Amapá"
      WHEN CONTAINS(page, "/ba/") OR ENDSWITH(page, "/ba") THEN "Bahia"
      WHEN CONTAINS(page, "/ce/") OR ENDSWITH(page, "/ce") THEN "Ceará"
      WHEN CONTAINS(page, "/df/") OR ENDSWITH(page, "/df") THEN "Distrito Federal"
      WHEN CONTAINS(page, "/es/") OR ENDSWITH(page, "/es") THEN "Espírito Santo"
      WHEN CONTAINS(page, "/go/") OR ENDSWITH(page, "/go") THEN "Goiás"
      WHEN CONTAINS(page, "/ma/") OR ENDSWITH(page, "/ma") THEN "Maranhão"
      WHEN CONTAINS(page, "/mg/") OR ENDSWITH(page, "/mg") THEN "Minas Gerais"
      WHEN CONTAINS(page, "/ms/") OR ENDSWITH(page, "/ms") THEN "Mato Grosso Do Sul"
      WHEN CONTAINS(page, "/mt/") OR ENDSWITH(page, "/mt") THEN "Mato Grosso"
      WHEN CONTAINS(page, "/pa/") OR ENDSWITH(page, "/pa") THEN "Pará"
      WHEN CONTAINS(page, "/pb/") OR ENDSWITH(page, "/pb") THEN "Paraíba"
      WHEN CONTAINS(page, "/pe/") OR ENDSWITH(page, "/pe") THEN "Pernambuco"
      WHEN CONTAINS(page, "/pi/") OR ENDSWITH(page, "/pi") THEN "Piauí"
      WHEN CONTAINS(page, "/pr/") OR ENDSWITH(page, "/pr") THEN "Paraná"
      WHEN CONTAINS(page, "/rj/") OR ENDSWITH(page, "/rj") THEN "Rio De Janeiro"
      WHEN CONTAINS(page, "/rn/") OR ENDSWITH(page, "/rn") THEN "Rio Grande Do Norte"
      WHEN CONTAINS(page, "/ro/") OR ENDSWITH(page, "/ro") THEN "Rondônia"
      WHEN CONTAINS(page, "/rr/") OR ENDSWITH(page, "/rr") THEN "Roraima"
      WHEN CONTAINS(page, "/rs/") OR ENDSWITH(page, "/rs") THEN "Rio Grande Do Sul"
      WHEN CONTAINS(page, "/sc/") OR ENDSWITH(page, "/sc") THEN "Santa Catarina"
      WHEN CONTAINS(page, "/se/") OR ENDSWITH(page, "/se") THEN "Sergipe"
      WHEN CONTAINS(page, "/sp/") OR ENDSWITH(page, "/sp") THEN "São Paulo"
      WHEN CONTAINS(page, "/to/") OR ENDSWITH(page, "/to") THEN "Tocantins" 
      WHEN CONTAINS(page, "/op/") OR ENDSWITH(page, "/op") THEN "Outros Paises"     
    END AS page_state
  FROM
    substructures
  WHERE
    domain = "wimoveis"
    AND substructure IN ("Other Transactional")
),
wimoveis_region_patterns_group AS (
  SELECT
    DISTINCT(page) AS page
  FROM
    wimoveis_region_patterns
),
imovelweb_region_patterns AS (
  SELECT 
    *
  FROM 
    substructures
  WHERE
    domain = "imovelweb"
    AND substructure IN ("Imobiliaria", "Other Transactional")
),
imovelweb_region_patterns_group AS (
  SELECT
    DISTINCT(page) AS page
  FROM
    imovelweb_region_patterns
  GROUP BY page
),
casamineira_match_grouped AS (
  SELECT
    page,
    state,
    city,
    neighborhood
  FROM
    casamineira_region_patterns_group AS cmrpg
  LEFT JOIN
    datalake_gsheets_clean.brazilian_regions_url AS bru
      ON CHARINDEX(bru.url_casamineira_region, cmrpg.page) > 0
  QUALIFY ROW_NUMBER() OVER(
    PARTITION BY cmrpg.page
    ORDER BY LENGTH(bru.url_casamineira_region) DESC
  ) = 1
),
casamineira_match AS (
  SELECT
    cmrp.keyword,
    cmrp.keyword_clean,
    cmrp.page,
    cmrp.structure,
    cmrp.business_context,
    cmrp.site_url,
    cmrp.device,
    cmrp.domain,
    cmrp.country,
    cmmg.state,
    cmmg.city,
    cmmg.neighborhood,
    cmrp.position,
    cmrp.impressions,
    cmrp.clicks,
    cmrp.ctr,
    cmrp.posimp,
    cmrp.is_branded,
    cmrp.dt_created,
    cmrp.year,
    cmrp.month,
    cmrp.day
  FROM 
    casamineira_region_patterns AS cmrp
  LEFT JOIN 
    casamineira_match_grouped AS cmmg
      ON cmrp.page = cmmg.page
),
wimoveis_match_grouped AS (
  SELECT
    page,
    state,
    city,
    neighborhood
  FROM
    wimoveis_region_patterns_group AS wirpg
  LEFT JOIN
    datalake_gsheets_clean.brazilian_regions_url AS bru
      ON CHARINDEX(bru.url_wimoveis_region, wirpg.page) > 0
  QUALIFY ROW_NUMBER() OVER(
    PARTITION BY wirpg.page
    ORDER BY LENGTH(bru.url_wimoveis_region) DESC
  ) = 1
),
wimoveis_match AS (
  SELECT
    wirp.keyword,
    wirp.keyword_clean,
    wirp.page,
    wirp.structure,
    wirp.business_context,
    wirp.site_url,
    wirp.device,
    wirp.domain,
    wirp.country,
    wimg.state,
    wimg.city,
    wimg.neighborhood,
    wirp.position,
    wirp.impressions,
    wirp.clicks,
    wirp.ctr,
    wirp.posimp,
    wirp.is_branded,
    wirp.dt_created,
    wirp.year,
    wirp.month,
    wirp.day
  FROM 
    wimoveis_region_patterns AS wirp
  LEFT JOIN 
    wimoveis_match_grouped AS wimg
      ON wirp.page = wimg.page
),
imovelweb_match_grouped AS (
  SELECT
    page,
    state,
    city,
    neighborhood
  FROM
    imovelweb_region_patterns_group AS iwrp
  LEFT JOIN
    datalake_gsheets_clean.brazilian_regions_url AS bru
      ON CHARINDEX(bru.url_imovelweb_region, iwrp.page) > 0
  QUALIFY ROW_NUMBER() OVER(
    PARTITION BY iwrp.page
    ORDER BY LENGTH(bru.url_imovelweb_region) DESC
  ) = 1
),
imovelweb_match AS (
  SELECT
    iwrp.keyword,
    iwrp.keyword_clean,
    iwrp.page,
    iwrp.structure,
    iwrp.business_context,
    iwrp.site_url,
    iwrp.device,
    iwrp.domain,
    iwrp.country,
    iwmg.state,
    iwmg.city,
    iwmg.neighborhood,
    iwrp.position,
    iwrp.impressions,
    iwrp.clicks,
    iwrp.ctr,
    iwrp.posimp,
    iwrp.is_branded,
    iwrp.dt_created,
    iwrp.year,
    iwrp.month,
    iwrp.day
  FROM 
    imovelweb_region_patterns AS iwrp
  LEFT JOIN 
    imovelweb_match_grouped AS iwmg
      ON iwmg.page = iwrp.page
),
non_match AS (
  SELECT
    keyword,
    keyword_clean,
    page,
    structure,
    business_context,
    site_url,
    device,
    domain,
    country,
    NULL AS state,
    NULL AS city,
    NULL AS neighborhood,
    position,
    impressions,
    clicks,
    ctr,
    posimp,
    is_branded,
    dt_created,
    year,
    month,
    day
  FROM 
    substructures
  WHERE
    (
      domain = "casamineira"
      AND substructure NOT IN ("Logradouro", "Ponto de Interesse", "Condominio", "imobiliaria", "Other Transactional")
    ) OR (
      domain = "wimoveis"
      AND substructure NOT IN ("Other Transactional")
    ) OR (
      domain = "imovelweb"
      AND substructure NOT IN ("Logradouro", "Ponto de Interesse", "Condominio", "Imobiliaria", "Other Transactional")
    )
),
result_data AS (
  SELECT
    *
  FROM 
    casamineira_match
  UNION
  SELECT
    *
  FROM 
    wimoveis_match
  UNION
  SELECT
    *
  FROM 
    imovelweb_match
  UNION
  SELECT
    *
  FROM 
    non_match
)
SELECT
  keyword,
  keyword_clean,
  page,
  structure,
  business_context,
  site_url,
  device,
  domain,
  country,
  state,
  city,
  neighborhood,
  position,
  impressions,
  clicks,
  ctr,
  posimp,
  is_branded,
  CASE 
    WHEN state IS NOT NULL THEN 1
    ELSE 0
  END AS has_region,
  dt_created,
  year,
  month,
  day
FROM
  result_data
