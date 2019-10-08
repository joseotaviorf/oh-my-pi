WITH
apts_iptu_sp AS (
  SELECT
    ea.setor_quadra || '.' || ea.numero_condominio || '.' || ea.codlog_imovel || '.' || ea.numero_imovel AS building_address_sk,
    ea.setor_quadra || '.' || ea.numero_condominio AS building_sk,
    ea.setor_quadra,
    ea.numero_condominio,
    ea.codlog_imovel,
    ea.numero_imovel,
    ea.formatted_address,
    geo.lat,
    geo.lng,
    geo.geocoded_address AS google_formatted_address,
    'SP' as uf,
    'São Paulo' as municipio,
    COUNT(1) as number_of_units,
    CAST(ROUND(AVG(TRY(CAST(ea.quantidade_pavimentos AS REAL)))) AS BIGINT) AS quantidade_pavimentos,
    CAST(ROUND(AVG(TRY(CAST(ea.ano_construcao_corrigido AS REAL)))) AS BIGINT) AS ano_construcao_corrigido,
    CAST(ROUND(AVG(TRY(CAST(ea.area_terreno AS REAL)))) AS BIGINT) AS area_terreno,
    CAST(ROUND(AVG(TRY(CAST(ea.area_construida AS REAL)))) AS BIGINT) AS area_construida,
    CAST(ROUND(AVG(TRY(CAST(ea.area_ocupada AS REAL)))) AS BIGINT) AS area_ocupada,
    CAST(ROUND(AVG(TRY(CAST(regexp_replace(ea.valor_m2_terreno, '\,', '.') AS REAL)))) AS BIGINT) AS valor_m2_terreno,
    CAST(ROUND(AVG(TRY(CAST(regexp_replace(ea.valor_m2_construcao, '\,', '.') AS REAL)))) AS BIGINT) AS valor_m2_construcao
  FROM datalake_raw.external_sp_apts AS ea
  JOIN datalake_raw.sp_houses_geocoded_addresses AS geo
    ON ea.bldg_address_id = geo.bldg_address_id
  WHERE ea.numero_imovel IS NOT NULL AND TRY_CAST(ea.numero_imovel AS BIGINT) IS NOT NULL
    AND geo.lat IS NOT NULL AND geo.lat != ''
  GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12
),
listings AS (
  SELECT
    l.sk_house_listing,
    l.house_lat,
    l.house_lng,
    regexp_extract(l.house_number, '\d+$') AS extracted_house_number
  FROM datalake_clean.ods_dim_house_listing l
),
listings_join_iptu AS (
  WITH
  radius AS (
    SELECT 1.0 AS "radius_km"
  )
  SELECT
    l.sk_house_listing,
    i.building_address_sk,
    ST_DISTANCE(
      ST_POINT(TRY(CAST(l.house_lng AS REAL)), TRY(CAST(l.house_lat AS REAL))),
      ST_POINT(TRY(CAST(i.lng AS REAL)), TRY(CAST(i.lat AS REAL)))
    ) AS distance_meters
  FROM listings AS l
  INNER JOIN apts_iptu_sp AS i
    ON (
      ST_DISTANCE(
        ST_POINT(TRY(CAST(l.house_lng AS REAL)), TRY(CAST(l.house_lat AS REAL))),
        ST_POINT(TRY(CAST(i.lng AS REAL)), TRY(CAST(i.lat AS REAL)))
      ) <= ((SELECT radius_km FROM radius) / (111.321 * COS(RADIANS(TRY(CAST(i.lat AS REAL))))))
    )
    AND CAST(i.numero_imovel AS BIGINT) = CAST(l.extracted_house_number AS BIGINT)
),
listings_join_iptu_min_distance AS (
  WITH
  ordered AS (
    SELECT
      *,
      ROW_NUMBER() OVER(PARTITION BY sk_house_listing, building_address_sk ORDER BY distance_meters DESC) AS distance_order
    FROM listings_join_iptu
  )
  SELECT * FROM ordered WHERE distance_order = 1
)
SELECT
  l.sk_house_listing,
  i.*
FROM listings l
LEFT JOIN listings_join_iptu_min_distance lj ON l.sk_house_listing = lj.sk_house_listing
LEFT JOIN apts_iptu_sp i ON lj.building_address_sk = i.building_address_sk
