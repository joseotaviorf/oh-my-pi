WITH
bldgs AS (
  SELECT
    c.tipo_registro,
    c.indicador_full_diario,
    c.tipo_atualizacao,
    c.cnpj,
    c.matriz_filial,
    c.razao_social,
    c.nome_fantasia,
    c.situacao_cadastral,
    c.dt_situacao_cadastral,
    c.motivo_situacao_cadastral,
    c.nm_cidade_exterior,
    c.cod_pais,
    c.nm_pais,
    c.cod_natureza_juridica,
    c.dt_inicio_atividade,
    c.cnae_fiscal,
    c.tipo_logradouro,
    c.logradouro,
    c.numero,
    regexp_extract(regexp_replace(trim(c.numero), '[,;\-\.]'), '\d+$') as extracted_number,
    c.complemento,
    c.bairro,
    c.cep,
    c.uf,
    c.cod_municipio,
    c.municipio,
    c.telefone_1,
    c.telefone_2,
    c.fax,
    c.email,
    c.quali_responsavel,
    c.capital_social,
    c.porte_empresa,
    c.opcao_simples,
    c.dt_opcao_simples,
    c.dt_exclusao_simples,
    c.opcao_mei,
    c.situacao_especial,
    c.dt_situacao_especial,
    c.formatted_address,
    c.comercial,
    c.sem_numero,
    c.hash,
    a.geocode,
    a.geocode_hash,
    a.google_formatted_address,
    a.lat,
    a.lng,
    a.place_id,
    a.types
  FROM datalake_raw.cnpj_br_condos c
  INNER JOIN datalake_raw.cnpj_br_condos_geocoded_addresses a ON c.hash = a.hash
  WHERE a.lat IS NOT NULL
    AND a.lat != ''
),
doorman AS (
  SELECT
    d.*,
    CASE
      WHEN COALESCE(d.work_place_id, '') != '' AND COALESCE(d.work_house_number, '') != '' THEN d.work_house_number
      ELSE regexp_extract(regexp_replace(trim(d.work_address), '[,;\-\.]'), '\d+$')
    END AS extracted_work_house_number,
    CASE
      WHEN COALESCE(d.work_place_id, '') != '' THEN d.work_address
      ELSE trim(regexp_replace(regexp_replace(d.work_address, regexp_extract(regexp_replace(trim(d.work_address), '[,;\-\.]'), '\d+$')), '[,;\-\.]')) || ', ' || regexp_extract(regexp_replace(trim(d.work_address), '[,;\-\.]'), '\d+$') || ' ' || d.work_city
    END AS formatted_address,
    COALESCE(a.google_formatted_address, d.work_address) AS google_formatted_address,
    COALESCE(a.lat, CAST(d.work_lat AS VARCHAR)) AS lat,
    COALESCE(a.lng, CAST(d.work_lng AS VARCHAR)) AS lng,
    u.telefone_principal,
    u.nome,
    u.dadosafiliado_ativo,
    d.ts_joined_program AS ts_joined_program_timestamp,
    leads.lead_activity
  FROM datalake_clean.ods_dim_user_doorman d
  LEFT JOIN datalake_raw.doorman_geocoded_addresses a ON d.id_user_doorman = CAST(a.id_user_doorman AS INTEGER)
  JOIN datalake_clean.ods_dim_user u ON d.sk_user_affiliate = u.dados_afiliado_id
  LEFT JOIN (
      SELECT dim_user_affiliate.sk_user AS sk_user,
             max(DATE(dim_date_lead.date)) AS last_date_lead,
             min(DATE(dim_date_lead.date)) AS first_date_lead,
             CASE
               WHEN max(DATE(dim_date_lead.date)) IS NULL THEN 'no referral'
               WHEN max(DATE(dim_date_lead.date)) >= current_date - interval '30' day THEN 'referral last 30 days'
               WHEN max(DATE(dim_date_lead.date)) >= current_date - interval '90' day AND max(DATE(dim_date_lead.date)) < current_date - interval '30' day THEN 'referral last 90 days'
               WHEN max(DATE(dim_date_lead.date)) >= current_date - interval '180' day AND max(DATE(dim_date_lead.date)) < current_date - interval '90' day THEN 'referral last 180 days'
               ELSE 'referral more than 180 days'
             END as lead_activity
      FROM datalake_clean.ods_fact_house_listing_flows AS fact_house_listing_flows_affiliates
      FULL OUTER JOIN
        (SELECT *
         FROM datalake_clean.ods_dim_user
         WHERE dados_afiliado_id IS NOT NULL) AS dim_user_affiliate ON CAST(fact_house_listing_flows_affiliates.sk_user_lead_affiliate AS INTEGER) = dim_user_affiliate.sk_user
      LEFT JOIN datalake_clean.ods_dim_date AS dim_date_lead ON dim_date_lead.sk_date = fact_house_listing_flows_affiliates.sk_lead_date
      WHERE fact_house_listing_flows_affiliates.sk_lead_date != '-1'
      GROUP BY dim_user_affiliate.sk_user
    ) AS leads
      ON u.sk_user = leads.sk_user
    WHERE
      (
        COALESCE(a.lat, '') != ''
        AND COALESCE(a.lng, '') != ''
        AND COALESCE(
          regexp_extract(regexp_replace(trim(d.work_address), '[,;\-\.]'), '\d+$')
          , '') != ''
      )
      OR COALESCE(d.work_place_id, '') != ''
)
SELECT
  bldgs.tipo_registro,
  bldgs.indicador_full_diario,
  bldgs.tipo_atualizacao,
  bldgs.cnpj,
  bldgs.matriz_filial,
  bldgs.razao_social,
  bldgs.nome_fantasia,
  bldgs.situacao_cadastral,
  bldgs.dt_situacao_cadastral,
  bldgs.motivo_situacao_cadastral,
  bldgs.nm_cidade_exterior,
  bldgs.cod_pais,
  bldgs.nm_pais,
  bldgs.cod_natureza_juridica,
  bldgs.dt_inicio_atividade,
  bldgs.cnae_fiscal,
  bldgs.tipo_logradouro,
  bldgs.logradouro,
  bldgs.numero,
  bldgs.extracted_number,
  bldgs.complemento,
  bldgs.bairro,
  bldgs.cep,
  bldgs.uf,
  bldgs.cod_municipio,
  bldgs.municipio,
  bldgs.telefone_1,
  bldgs.telefone_2,
  bldgs.fax,
  bldgs.email,
  bldgs.quali_responsavel,
  bldgs.capital_social,
  bldgs.porte_empresa,
  bldgs.opcao_simples,
  bldgs.dt_opcao_simples,
  bldgs.dt_exclusao_simples,
  bldgs.opcao_mei,
  bldgs.situacao_especial,
  bldgs.dt_situacao_especial,
  bldgs.formatted_address,
  bldgs.comercial,
  bldgs.sem_numero,
  bldgs.hash,
  bldgs.geocode,
  bldgs.geocode_hash,
  bldgs.google_formatted_address,
  COALESCE(bldgs.lat, bldgs_doormen.doorman_lat[1]) AS lat,
  COALESCE(bldgs.lng, bldgs_doormen.doorman_lng[1]) AS lng,
  bldgs.place_id,
  bldgs.types,
  bldgs_doormen.doorman_ct,
  bldgs_doormen.doorman_phone,
  bldgs_doormen.doorman_name,
  bldgs_doormen.doorman_active,
  bldgs_doormen.doorman_joined_date,
  bldgs_doormen.latest_doorman_joined_date,
  bldgs_doormen.earliest_doorman_joined_date,
  CASE WHEN bldgs_doormen.doorman_ct > 0 THEN true ELSE false END AS has_doorman,
  CASE
    WHEN
      contains(bldgs_doormen.doorman_active, 'referral last 30 days') OR
      contains(bldgs_doormen.doorman_active, 'referral last 90 days') OR
      contains(bldgs_doormen.doorman_active, 'referral last 180 days')
    THEN true
    ELSE false
  END AS has_active_doorman,
  CASE
    WHEN contains(bldgs_doormen.doorman_active, 'referral last 30 days') THEN 'referral last 30 days'
    WHEN contains(bldgs_doormen.doorman_active, 'referral last 90 days') THEN 'referral last 90 days'
    WHEN contains(bldgs_doormen.doorman_active, 'referral last 180 days') THEN 'referral last 180 days'
    WHEN contains(bldgs_doormen.doorman_active, 'referral more than 180 days') THEN 'referral more than 180 days'
    WHEN contains(bldgs_doormen.doorman_active, 'no referral') THEN 'no referral'
  END AS most_active_doorman
FROM bldgs
FULL OUTER JOIN
  (SELECT
    COALESCE(b.hash,
      CAST(ROUND(CAST(d.lng AS double), 4) AS varchar) || ',' || CAST(ROUND(CAST(d.lat AS double), 4) AS varchar) || ',' || d.extracted_work_house_number
    ) as hash,
    COUNT(*) AS doorman_ct,
    array_agg(telefone_principal) AS doorman_phone,
    array_agg(TRIM(nome)) AS doorman_name,
    array_agg(lead_activity) AS doorman_active,
    array_agg(ts_joined_program) AS doorman_joined_date,
    MAX(ts_joined_program_timestamp) AS latest_doorman_joined_date,
    MIN(ts_joined_program_timestamp) AS earliest_doorman_joined_date,
    array_agg(d.lng) AS doorman_lng,
    array_agg(d.lat) AS doorman_lat
  FROM doorman AS d
  LEFT JOIN bldgs AS b
  ON
    ST_WITHIN(
      ST_POINT(CAST(b.lng AS double), CAST(b.lat AS DOUBLE)),
      ST_BUFFER(
        -- 1 degree 110752 meters at latitude -23
        -- 100 meters 0.00090291823 degrees
        ST_POINT(CAST(d.lng AS double), CAST(d.lat AS DOUBLE)), 0.00090291823
      )
    )
    AND CAST(b.extracted_number AS INTEGER) = CAST(d.extracted_work_house_number AS INTEGER)
    -- leading zero issue here?
    -- also: guarantee only 1 bldg match per doorman (nearest?)
  GROUP BY 1) AS bldgs_doormen
ON bldgs.hash = bldgs_doormen.hash
;
