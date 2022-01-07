WITH doorman AS (
  SELECT
    d.*,
    CASE
      WHEN d.work_place_id IS NOT NULL AND d.work_house_number IS NOT NULL THEN d.work_house_number
      ELSE regexp_extract(regexp_replace(trim(d.work_address), '[,;\-\.]'), '\d+$')
    END AS extracted_work_house_number,
    CASE
      WHEN d.work_place_id IS NOT NULL THEN d.work_address
      ELSE trim(regexp_replace(regexp_replace(d.work_address, regexp_extract(regexp_replace(trim(d.work_address), '[,;\-\.]'), '\d+$')), '[,;\-\.]')) || ', ' || regexp_extract(regexp_replace(trim(d.work_address), '[,;\-\.]'), '\d+$') || ' ' || d.work_city
    END AS formatted_address,
    COALESCE(a.google_formatted_address, d.work_address) AS google_formatted_address,
    COALESCE(a.lat, CAST(d.work_lat AS VARCHAR)) AS lat,
    COALESCE(a.lng, CAST(d.work_lng AS VARCHAR)) AS lng,
    u.telefone_principal,
    u.nome,
    u.dadosafiliado_ativo,
    CASE WHEN d.ts_joined_program IS NOT NULL THEN
      d.ts_joined_program
    ELSE NULL END AS ts_joined_program_timestamp,
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
      WHERE dim_date_lead.date != '' AND dim_date_lead.date IS NOT NULL
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
apts_iptu_sp AS (
  SELECT
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
    ea.complemento_imovel,
    geo.lat,
    geo.lng,
    geo.geocoded_address AS google_formatted_address,
    'SP' as uf,
    'São Paulo' as municipio
  FROM datalake_raw.external_sp_apts AS ea
  LEFT JOIN datalake_raw.sp_houses_geocoded_addresses AS geo
    ON ea.bldg_address_id = geo.bldg_address_id
  WHERE ea.numero_imovel IS NOT NULL AND TRY_CAST(ea.numero_imovel AS INTEGER) IS NOT NULL
    AND geo.lat IS NOT NULL AND geo.lat != ''
),
apts_direct AS (
  SELECT
    i.direct_id || '/' || i.proprietario_cpf_cnpj AS property_person_id,
    NULL as setor_quadra,
    NULL as ano_construcao_corrigido,
    i.proprietario_cpf_cnpj AS cpf_cnpj,
    i.proprietario_nome AS nome_direct,
    NULL as sexo,
    NULL as idade,
    NULL as obito,
    NULL as qtd_ocorrencias,
    NULL as contribuinte_1_ou_2,
    proprietario_tipo as tipo_contribuinte_1,
    NULL as tipo_contribuinte_2,
    a.formatted_address,
    i.endereco_numero as numero_imovel,
    i.endereco_complemento as complemento_imovel,
    a.lat,
    a.lng,
    a.google_formatted_address,
    i.uf,
    i.municipio
  FROM datalake_raw.external_iptu_owners i
  JOIN datalake_raw.external_iptu_owners_addresses a ON i.direct_id = a.direct_id
  WHERE
    i.endereco_numero IS NOT NULL AND TRY_CAST(i.endereco_numero AS INTEGER) IS NOT NULL
    AND COALESCE(a.lat, '') IS NOT NULL AND COALESCE(a.lat, '') != ''
    AND COALESCE(i.proprietario_cpf_cnpj, '') != ''
),
apts AS (
  SELECT * FROM apts_iptu_sp
  UNION ALL
  SELECT * FROM apts_direct
),
doorman_join_apts_owners AS (
  SELECT
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
    ON ST_WITHIN(
      ST_POINT(CAST(a.lng AS double), CAST(a.lat AS DOUBLE)),
      ST_BUFFER(
        -- 1 degree 110752 meters at latitude -23
        -- 100 meters 0.00090291823 degrees
        ST_POINT(CAST(d.lng AS double), CAST(d.lat AS DOUBLE)), 0.00090291823
      )
    )
    AND
    CAST(a.numero_imovel AS INTEGER) = CAST(d.extracted_work_house_number AS INTEGER)
  GROUP BY a.property_person_id
)
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
    ELSE 'no referral'
  END AS most_active_doorman,
  a.*
FROM apts a
LEFT JOIN doorman_join_apts_owners d ON a.property_person_id = d.property_person_id
ORDER BY a.google_formatted_address, a.complemento_imovel
