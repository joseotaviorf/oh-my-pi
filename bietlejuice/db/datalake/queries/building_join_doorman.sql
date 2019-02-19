WITH
external_sp_apts AS (SELECT *,
  SUBSTR(numero_contribuinte, 1, 6) AS setor_quadra,
  SUBSTR(numero_contribuinte, 1, 10) AS setor_quadra_lote,
  SUBSTR(numero_contribuinte, 1, 6) || '.' || numero_condominio AS bldg_id,
  SUBSTR(numero_contribuinte, 1, 6) || '.' || numero_condominio || '.' || codlog_imovel || '.' || numero_imovel AS bldg_address_id,
  COALESCE(numero_imovel, '0') AS address_number,
  nome_lougradouro_imovel || ', ' || COALESCE(numero_imovel, '0') || ' São Paulo, SP ' || cep_imovel AS formatted_address,
  ROW_NUMBER() OVER(PARTITION BY SUBSTR(numero_contribuinte, 1, 6) || '.' || codlog_imovel || '.' || numero_imovel
                        ORDER BY SUBSTR(numero_contribuinte, 1, 6) || '.' || codlog_imovel || '.' || numero_imovel) AS bldg_address_id_row_key
FROM datalake_raw.external_sp_houses
WHERE (
    tipo_uso_imovel = ANY (VALUES 'Apartamento em condomínio', 'Flat residencial em condomínio', 'Flat de uso comercial (semelhante a hotel)')
    OR
    SUBSTR(numero_contribuinte, 1, 6) || '.' || numero_condominio = ANY (VALUES '147075.01-9', '015007.09-4', '160283.01-9', '162001.08-6', '086108.01-9', '013022.16-7', '039189.02-7', '054070.07-8', '081133.04-3', '083205.04-3', '086108.01-9', '169207.03-5')
  )
),
bldgs_stats AS (
  SELECT stats.*,
    info.formatted_address AS bldg_formatted_address,
    info.address_number AS bldg_street_num,
    info.numero_condominio AS bldg_condo_num,
    info.codlog_imovel AS bldg_codlog,
    info.nome_lougradouro_imovel AS bldg_street_name,
    info.bldg_id,
    info.setor_quadra,
    info.setor_quadra_lote,
    info.bairro_imovel AS bldg_neighborhood,
    info.quantidade_esquinas_frentes AS bldg_corners_fronts_num,
    REPLACE(info.valor_m2_terreno, ',', '.') AS bldg_terrain_sq_m_value,
    REPLACE(info.valor_m2_construcao, ',', '.') AS bldg_construction_sq_m_value,
    info.tipo_uso_imovel AS bldg_user_type,
    info.tipo_padrao_construcao AS bldg_construction_standard,
    info.tipo_terreno AS bldg_terrain_type,
    geo.lat,
    geo.lng,
    geo.geocoded_address
  FROM
  (SELECT
    bldg_address_id,
    COUNT(numero_contribuinte) AS apt_count,
    AVG(CAST(area_terreno AS double)) AS mean_terrain_area,
    AVG(CAST(area_construida AS double)) AS mean_apt_built_area,
    MIN(CAST(area_construida AS double)) AS min_apt_built_area,
    MAX(CAST(area_construida AS double)) AS max_apt_built_area,
    SUM(CAST(area_construida AS double)) AS sum_apt_built_area,
    AVG(CAST(ano_construcao_corrigido AS double)) AS mean_year_built,
    AVG(CAST(quantidade_pavimentos AS double)) AS mean_floors_num
  -- FROM apts
  FROM external_sp_apts AS apts
  GROUP BY bldg_address_id) AS stats
  LEFT JOIN
    (SELECT * FROM external_sp_apts WHERE bldg_address_id_row_key = 1) AS info
    ON stats.bldg_address_id = info.bldg_address_id
  LEFT JOIN datalake_raw.sp_houses_geocoded_addresses AS geo
    ON info.bldg_address_id = geo.bldg_address_id
  WHERE geo.lat IS NOT NULL
),
doorman AS (
  SELECT
    d.*,
    regexp_extract(regexp_replace(trim(d.work_address), '[,;\-\.]'), '\d+$') as extracted_work_house_number,
    trim(regexp_replace(regexp_replace(d.work_address, regexp_extract(regexp_replace(trim(d.work_address), '[,;\-\.]'), '\d+$')), '[,;\-\.]')) || ', ' || regexp_extract(regexp_replace(trim(d.work_address), '[,;\-\.]'), '\d+$') || ' ' || d.work_city as formatted_address,
    a.google_formatted_address,
    a.lat,
    a.lng,
    u.telefone_principal,
    u.nome,
    u.dadosafiliado_ativo,
    CASE WHEN d.ts_joined_program != '' AND d.ts_joined_program IS NOT NULL THEN
      CAST(d.ts_joined_program as timestamp)
    ELSE NULL END AS ts_joined_program_timestamp
  FROM datalake_clean.ods_dim_user_doorman d
  LEFT JOIN datalake_raw.doorman_geocoded_addresses a ON d.id_user_doorman = a.id_user_doorman
  JOIN datalake_clean.ods_dim_user u ON CAST(d.sk_user_affiliate AS VARCHAR) = u.dados_afiliado_id
  WHERE work_city = 'São Paulo'
    AND a.lat IS NOT NULL
)
SELECT
  bldgs_stats.*,
  bldgs_doormen.doorman_ct,
  bldgs_doormen.doorman_phone,
  bldgs_doormen.doorman_name,
  bldgs_doormen.doorman_active,
  bldgs_doormen.doorman_joined_date,
  bldgs_doormen.latest_doorman_joined_date,
  bldgs_doormen.earliest_doorman_joined_date,
  CASE WHEN bldgs_doormen.doorman_ct > 0 THEN true ELSE false END AS has_doorman,
  contains(bldgs_doormen.doorman_active, '1') AS has_active_doorman
FROM bldgs_stats
LEFT JOIN
  (SELECT
    b.bldg_address_id,
    COUNT(*) AS doorman_ct,
    array_agg(telefone_principal) AS doorman_phone,
    array_agg(TRIM(nome)) AS doorman_name,
    array_agg(dadosafiliado_ativo) AS doorman_active,
    array_agg(ts_joined_program) AS doorman_joined_date,
    MAX(ts_joined_program_timestamp) AS latest_doorman_joined_date,
    MIN(ts_joined_program_timestamp) AS earliest_doorman_joined_date
  FROM doorman AS d
  JOIN bldgs_stats AS b
  ON
    ST_WITHIN(
      ST_POINT(CAST(b.lng AS double), CAST(b.lat AS DOUBLE)),
      ST_BUFFER(
        -- 1 degree 110752 meters at latitude -23
        -- 100 meters 0.00090291823 degrees
        ST_POINT(CAST(d.lng AS double), CAST(d.lat AS DOUBLE)), 0.00090291823
      )
    )
    AND CAST(b.bldg_street_num AS INTEGER) = CAST(d.extracted_work_house_number AS INTEGER)
    -- leading zero issue here?
    -- also: guarantee only 1 bldg match per doorman (nearest?)
  GROUP BY b.bldg_address_id) AS bldgs_doormen
ON bldgs_stats.bldg_address_id = bldgs_doormen.bldg_address_id
;
