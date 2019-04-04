WITH doorman AS (
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
    ELSE NULL END AS ts_joined_program_timestamp,
    leads.lead_activity
  FROM datalake_clean.ods_dim_user_doorman d
  LEFT JOIN datalake_raw.doorman_geocoded_addresses a ON d.id_user_doorman = a.id_user_doorman
  JOIN datalake_clean.ods_dim_user u ON CAST(d.sk_user_affiliate AS VARCHAR) = u.dados_afiliado_id
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
         WHERE dados_afiliado_id IS NOT NULL) AS dim_user_affiliate ON fact_house_listing_flows_affiliates.sk_user_lead_affiliate = dim_user_affiliate.sk_user
      LEFT JOIN datalake_clean.ods_dim_date AS dim_date_lead ON dim_date_lead.sk_date = fact_house_listing_flows_affiliates.sk_lead_date
      WHERE dim_date_lead.date != '' AND dim_date_lead.date IS NOT NULL
      GROUP BY dim_user_affiliate.sk_user
    ) AS leads
      ON u.sk_user = leads.sk_user
  WHERE work_city = 'São Paulo'
    AND a.lat IS NOT NULL
),
phones AS (
SELECT cpf, phone_number
FROM
  (SELECT
  	cpf,
    telefone as phone_number,
    ROW_NUMBER() OVER(PARTITION BY cpf ORDER BY ordem) AS row
  FROM datalake_raw.external_sp_houses_phones
  WHERE tipo = 'L') AS tmp
WHERE row IN (1, 2)
),
apts AS (
  SELECT
    ea.numero_contribuinte,
    -- ea.bldg_id,
    ea.bldg_address_id,
    ea.numero_contribuinte || '/' || ea.cpf_cnpj AS property_person_id,
    ea.setor_quadra,
    ea.ano_construcao_corrigido,
    ea.cpf_cnpj,
    ea.nome_direct,
    ea.sexo,
    ea.idade,
    ea.obito,
    ea.qtd_ocorrencias,
    ea.contribuinte_1_ou_2,
    ea.tipo_contribuinte_1,
    ea.tipo_contribuinte_2,
    ea.formatted_address,
    ea.numero_imovel,
    -- ea.nome_lougradouro_imovel,
    -- ea.address_number,
    ea.complemento_imovel
    -- ea.tipo_uso_imovel,
    -- ea.area_construida,
    -- ea.numero_condominio,
  FROM datalake_raw.external_sp_apts AS ea
  WHERE ea.numero_imovel IS NOT NULL AND TRY_CAST(ea.numero_imovel AS INTEGER) IS NOT NULL
    -- AND CAST(ea.qtd_ocorrencias AS INTEGER) > 1  -- owners with more than 1 apt
  -- drop duplicate property_person_id?
),
doorman_join_apts_owners AS (
  SELECT
    -- d.*,
    -- p.setor_quad,
    -- a.*
    a.property_person_id,
    COUNT(*) AS doorman_ct,
    array_agg(telefone_principal) AS doorman_phone,
    array_agg(TRIM(nome)) AS doorman_name,
    array_agg(lead_activity) AS doorman_active,
    array_agg(ts_joined_program) AS doorman_joined_date,
    MAX(ts_joined_program_timestamp) AS latest_doorman_joined_date,
    MIN(ts_joined_program_timestamp) AS earliest_doorman_joined_date
  FROM apts AS a
  INNER JOIN doorman AS d
    ON CAST(a.numero_imovel AS INTEGER) = CAST(d.extracted_work_house_number AS INTEGER)
  INNER JOIN datalake_raw.sp_quadras_polygons_buffer_50m AS p
    ON ST_INTERSECTS(
      ST_POINT(CAST(d.lng AS double), CAST(d.lat AS DOUBLE)),
      ST_POLYGON(p.geometry)
    )
    AND p.setor_quad = a.setor_quadra
  GROUP BY a.property_person_id
)
-- ,
-- apts_owners_counts AS (
--   SELECT
--     listing_id,
--     COUNT(*) AS possible_owners_count
--   FROM apts_owners
--   GROUP BY listing_id
--   HAVING COUNT(*) < 150
-- )
SELECT
  d.doorman_ct,
  d.doorman_phone,
  d.doorman_name,
  d.doorman_active,
  d.doorman_joined_date,
  d.latest_doorman_joined_date,
  d.earliest_doorman_joined_date,
  CASE
    WHEN
      contains(d.doorman_active, 'referral last 30 days') OR
      contains(d.doorman_active, 'referral last 90 days') OR
      contains(d.doorman_active, 'referral last 180 days')
    THEN true
    ELSE false
  END AS has_active_doorman,
  CASE
    WHEN contains(d.doorman_active, 'referral last 30 days') THEN 'referral last 30 days'
    WHEN contains(d.doorman_active, 'referral last 90 days') THEN 'referral last 90 days'
    WHEN contains(d.doorman_active, 'referral last 180 days') THEN 'referral last 180 days'
    WHEN contains(d.doorman_active, 'referral more than 180 days') THEN 'referral more than 180 days'
    WHEN contains(d.doorman_active, 'no referral') THEN 'no referral'
  END AS most_active_doorman,
  a.*
FROM apts a
INNER JOIN doorman_join_apts_owners d ON a.property_person_id = d.property_person_id
ORDER BY a.bldg_address_id, a.complemento_imovel
