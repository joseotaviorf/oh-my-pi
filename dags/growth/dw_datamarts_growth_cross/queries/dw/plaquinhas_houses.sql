WITH rent_ongoing_listings AS (
  ----------------------------
  -- Rent Ongoing Listings --
  ----------------------------
  SELECT
    /*+ RANGE_JOIN(f, 19000) */
    CAST(f.sk_house_listing / 1000 AS BIGINT) AS id_house,
    d.date AS dt_ongoing_listing,
    d.weekday_name,
    d.month_end,
    'Rent' AS business_context,
    dr.country_code,
    dr.city_group,
    dr.city_name,
    dr.name AS neighborhood,
    h.type
  FROM
    datalake_listing_temp.fact_house_listing_status_house AS f
    JOIN
      dw_public.dim_date AS d
        ON d.sk_date BETWEEN NULLIF(f.sk_status_start_date, -1) AND COALESCE(DATE_FORMAT(TO_DATE(NULLIF(sk_status_end_date, -1) :: STRING,'yyyyMMdd') - INTERVAL '1' day,'yyyyMMdd') :: BIGINT, DATE_FORMAT(CURRENT_DATE - INTERVAL '1' day, 'yyyyMMdd')) :: BIGINT
    LEFT JOIN
      dw_public.dim_region AS dr
        ON f.sk_region = dr.sk_region
    LEFT JOIN
      datalake_ebdb_listing.house AS h
        ON CAST(f.sk_house_listing / 1000 AS BIGINT) = h.id
  WHERE
    f.status_history IN ('publicado', 'PUBLISHED') -- consider only published status
      AND SUBSTRING(sk_house_listing, 10, 12) <> '000' -- consider only listings that already started publication
      AND date >= CURRENT_DATE - INTERVAL '2' year -- DATE('2023-01-01') -- Month when the campaign started
      AND f.sk_region > 0
      AND dr.country_code = 'BR'
  QUALIFY ROW_NUMBER() OVER(PARTITION BY f.sk_house_listing, d.date ORDER BY f.ts_status_start DESC NULLS FIRST) = 1
),
sale_ongoing_listings AS (
  ----------------------------
  -- Sale Ongoing Listings --
  ----------------------------
  SELECT
    CAST(f.sk_sale_listing / 1000 AS BIGINT) AS id_house,
    d.date AS dt_ongoing_listing,
    d.weekday_name,
    d.month_end,
    'Sale' AS business_context,
    dr.country_code,
    dr.city_group,
    dr.city_name,
    dr.name AS neighborhood,
    h.type
  FROM
    dw_sale.fact_listing_status AS f
    JOIN
      dw_public.dim_date AS d
        ON d.sk_date BETWEEN NULLIF(f.sk_status_start_date,-1) AND COALESCE(DATE_FORMAT(TO_DATE(NULLIF(sk_status_end_date, -1)::STRING, 'yyyyMMdd') - INTERVAL '1' day, 'yyyyMMdd')::BIGINT, DATE_FORMAT(CURRENT_DATE - INTERVAL '1' day, 'yyyyMMdd')::BIGINT)
    LEFT JOIN
      dw_public.dim_region AS dr
        ON f.sk_region = dr.sk_region
    LEFT JOIN
      datalake_ebdb_listing.house AS h
        ON CAST(f.sk_sale_listing / 1000 AS BIGINT) = h.id
  WHERE
    f.status_history IN ('publicado', 'PUBLISHED') -- consider only published status
    AND date >= CURRENT_DATE - INTERVAL '2' year -- DATE('2023-01-01') -- Month when the campaign started
    AND f.sk_region > 0
    AND dr.country_code = 'BR'
  QUALIFY ROW_NUMBER() OVER(PARTITION BY f.sk_sale_listing, d.date ORDER BY f.ts_status_started DESC) = 1
),
ol_detalhes AS (
  SELECT
    DISTINCT *
  FROM
    rent_ongoing_listings
  UNION ALL
  SELECT
    DISTINCT *
  FROM
    sale_ongoing_listings
),
ol AS (
  SELECT
    DISTINCT
    dt_ongoing_listing,
    id_house,
    coalesce(h.id_condo_parent, id_house) AS id_condo
  FROM
    ol_detalhes AS o
    LEFT JOIN
      datalake_ebdb_clean.house AS h
        ON h.id = o.id_house
  WHERE
    id_house IS NOT NULL
    AND dt_ongoing_listing >= (CURRENT_DATE - INTERVAL '2' year) --
),
installs_aux AS (
  -- Histórico de instalações inputados no GSheets --
  SELECT
    DISTINCT
    p.id_house,
    "boa instalação" AS plaquinha,
    NULL AS ressalva,
    1 AS tem_plaquinha_flg,
    0 AS condo_nao_permite_flg,
    p.installation_type AS tipo_install,
    DATE(dt_plaquinha) AS dt_install
  FROM
    datalake_gsheets_clean.branding_where_is_plaquinha AS p
  UNION ALL
    -- First Listings Installs --
  SELECT
    REGEXP_EXTRACT(d.subject, '(\\d+)', 0) AS id_house,
    GET_JSON_OBJECT(d.custom_fields, '$["[AQ] Tem plaquinha"]') AS plaquinha,
    GET_JSON_OBJECT(d.custom_fields, '$["[AQ] Ressalva de plaquinha"]') AS ressalva,
    CASE
      WHEN GET_JSON_OBJECT(d.custom_fields, '$["[AQ] Tem plaquinha"]') IN ('fraude_de_plaquinha', 'não_identificada', 'plaquinha_duplicada') THEN 0
      WHEN GET_JSON_OBJECT(d.custom_fields, '$["[AQ] Ressalva de plaquinha"]') IN ('pp_ou_condomínio_não_autoriza_instalação', 'placa_duplicada_aq', 'placa_de_ponta_cabeça_aq') THEN 0
      WHEN GET_JSON_OBJECT(d.custom_fields, '$["[AQ] Tem plaquinha"]') IN ('área_comum') AND GET_JSON_OBJECT(d.custom_fields, '$["[AQ] Ressalva de plaquinha"]') IN ('instalações_em_postes_e_árvores_aq', 'placa_colada_em_cima_de_outra_aq') THEN 0
      ELSE 1
    END AS tem_plaquinha_flg,
    CASE
      WHEN GET_JSON_OBJECT(d.custom_fields, '$["[AQ] Tem plaquinha"]') IN ('área_comum', 'fora_do_padrão', 'não_identificada', 'no_imóvel') AND GET_JSON_OBJECT(d.custom_fields, '$["[AQ] Ressalva de plaquinha"]') IN ('pp_ou_condomínio_não_autoriza_instalação') THEN 1
      ELSE 0
    END AS condo_nao_permite_flg,
    "photographer" AS tipo_install,
    MAX(DATE(p.dt_photos_uploaded)) AS dt_install
  FROM
    dw_customer_support.dim_ticket d
    LEFT JOIN
      dw_public.dim_photo_job p
        ON REGEXP_EXTRACT(d.subject, '(\\d+)', 0) = p.imovel_id
  WHERE
    d.group_name = 'Listing Quality [FOTOS] [SO]'
    AND REGEXP_EXTRACT(d.subject, '(\\d+)', 0) > 0
    AND GET_JSON_OBJECT(d.custom_fields, '$["[AQ] Tem plaquinha"]') is not null
  GROUP BY 1,2,3,4,5,6
  UNION ALL
    -- Ongoing Listings Installs - Motoboy --
  SELECT
    DISTINCT
    COALESCE(CAST(GET_JSON_OBJECT(custom_fields, '$["[SO] Código do Imóvel"]') AS BIGINT), REGEXP_EXTRACT(subject, '(\\d+)', 0)) AS id_house,
    CAST(GET_JSON_OBJECT(custom_fields, '$["[SO] Instalação realizada"]') AS VARCHAR(30)) AS plaquinha,
    CAST(GET_JSON_OBJECT(custom_fields, '$["[SO] Ressalva"]') AS VARCHAR(30)) AS ressalva,
    CASE
      WHEN CAST(GET_JSON_OBJECT(custom_fields, '$["[SO] Instalação realizada"]') AS VARCHAR(30)) = 'sim_instalação_realizada' AND CAST(GET_JSON_OBJECT(custom_fields, '$["[SO] Ressalva"]') AS VARCHAR(30)) IS NULL THEN 1
      WHEN CAST(GET_JSON_OBJECT(custom_fields, '$["[SO] Instalação realizada"]') AS VARCHAR(30)) = 'não_instalação_realizada' AND CAST(GET_JSON_OBJECT(custom_fields, '$["[SO] Ressalva"]') AS VARCHAR(30)) = 'já_tem_placa' THEN 1
      WHEN CAST(GET_JSON_OBJECT(custom_fields, '$["[SO] Instalação realizada"]') AS VARCHAR(30)) = 'com_ressalva_instalação_realizada' AND CAST(GET_JSON_OBJECT(custom_fields, '$["[SO] Ressalva"]') AS VARCHAR(30)) IN ('adesivo_em_parede/portão', 'entregue_à_portaria_ressalva', 'entregue_ao_pp_ressalva', 'instalação_em_poste/arvore', 'placa_randômica_ressalva', 'placa_sobre_placa') THEN 1
      ELSE 0
    END AS tem_plaquinha_flg,
    CASE
      WHEN CAST(GET_JSON_OBJECT(custom_fields, '$["[SO] Ressalva"]') AS VARCHAR(30)) IN ('pp_ou_condomínio_não_autoriza_instalação') THEN 1
      WHEN CAST(GET_JSON_OBJECT(custom_fields, '$["[SO] Ressalva"]') AS VARCHAR(30)) IN ('condôminio_não_permite') THEN 1
      ELSE 0
    END AS condo_nao_permite_flg,
    "motoboy" AS tipo_install,
    CAST(GET_JSON_OBJECT(custom_fields, '$["[SO] Data de instalação"]') AS VARCHAR(30)) AS dt_install
  FROM
    dw_customer_support.dim_ticket AS t
  WHERE
    group_name = 'Plaquinhas - Pedidos da FAQ [SO]'
    AND CAST(GET_JSON_OBJECT(custom_fields, '$["[SO] Serviço solicitado"]') AS VARCHAR(30)) = 'instalação_serviço_solicitado'
  UNION ALL
    -- Ongoing Listings Installs - PP Organico --
  SELECT
    DISTINCT
    p.id_house,
    "boa instalação" AS plaquinha,
    NULL AS ressalva,
    1 AS tem_plaquinha_flg,
    0 AS condo_nao_permite_flg,
    "owner" AS tipo_install,
    DATE(p.dt_install) AS dt_install
  FROM
    datalake_gsheets_clean.plaquinhas_installation_pp_organic AS p
  WHERE
    client_type = "Proprietário"
    AND p.id_house IS NOT NULL
),
installs AS (
  SELECT
    DISTINCT
    id_house,
    plaquinha,
    ressalva,
    tem_plaquinha_flg,
    condo_nao_permite_flg,
    tipo_install,
    dt_install,
    CASE
      WHEN tem_plaquinha_flg = 1 THEN dt_install
      ELSE NULL
    END AS dt_install_sucesso,
    CASE
      WHEN tem_plaquinha_flg = 0 THEN dt_install
      ELSE NULL
    END AS dt_install_sem_sucesso -- row_number() OVER(PARTITION BY id_house, tem_plaquinha_flg ORDER BY dt_install desc) as rn
  FROM
    installs_aux
  WHERE
    id_house > 1 -- and dt_install >= (CURRENT_DATE - INTERVAL '2' year) --
),
manutencao_aux AS (
  SELECT
    DISTINCT
    COALESCE(CAST(GET_JSON_OBJECT(custom_fields, '$["[SO] Código do Imóvel"]') AS BIGINT), REGEXP_EXTRACT(subject, '(\\d+)', 0)) AS id_house,
    CAST(GET_JSON_OBJECT(custom_fields, '$["[SO] Instalação realizada"]') AS VARCHAR(30)) AS plaquinha,
    CAST(GET_JSON_OBJECT(custom_fields, '$["[SO] Ressalva"]') AS VARCHAR(30)) AS ressalva,
    CASE
      WHEN CAST(GET_JSON_OBJECT(custom_fields, '$["[SO] Ressalva"]') AS VARCHAR(30)) IN ('condôminio_não_permite') THEN 0
      WHEN CAST(GET_JSON_OBJECT(custom_fields, '$["[SO] Instalação realizada"]') AS VARCHAR(30)) = 'sim_instalação_realizada' THEN 1
      WHEN CAST(GET_JSON_OBJECT(custom_fields, '$["[SO] Instalação realizada"]') AS VARCHAR(30)) = 'não_instalação_realizada' AND CAST(GET_JSON_OBJECT(custom_fields, '$["[SO] Ressalva"]') AS VARCHAR(30)) IN ('endereço_não_encontrado', 'imóvel_indisponível', 'recusa_de_pp', 'instalação_em_poste/arvore') THEN 0
      WHEN CAST(GET_JSON_OBJECT(custom_fields, '$["[SO] Instalação realizada"]') AS VARCHAR(30)) = 'com_ressalva_instalação_realizada' AND CAST(GET_JSON_OBJECT(custom_fields, '$["[SO] Ressalva"]') AS VARCHAR(30)) IN ('imóvel_indisponível', 'placa_incompatível_com_o_imóvel') THEN 0
      ELSE 1
    END AS tem_plaquinha_flg,
    CASE
      WHEN CAST(GET_JSON_OBJECT(custom_fields, '$["[SO] Ressalva"]') AS VARCHAR(30)) IN ('pp_ou_condomínio_não_autoriza_instalação') THEN 1
      WHEN CAST(GET_JSON_OBJECT(custom_fields, '$["[SO] Ressalva"]') AS VARCHAR(30)) IN ('condôminio_não_permite') THEN 1
      ELSE 0
    END as condo_nao_permite_flg,
    CAST(GET_JSON_OBJECT(custom_fields, '$["[SO] Serviço solicitado"]') AS VARCHAR(30)) AS tipo_manutencao,
    CAST(GET_JSON_OBJECT(custom_fields, '$["[SO] Data de instalação"]') AS VARCHAR(30)) as dt_manutencao
  FROM
    dw_customer_support.dim_ticket AS t
    LEFT JOIN
      datalake_ebdb_clean.house AS h
        ON COALESCE(CAST(GET_JSON_OBJECT(t.custom_fields, '$["[SO] Código do Imóvel"]') AS BIGINT), REGEXP_EXTRACT(t.subject, '(\\d+)', 0)) = h.id
  WHERE
    group_name = 'Plaquinhas - Pedidos da FAQ [SO]'
    AND CAST(GET_JSON_OBJECT(custom_fields, '$["[SO] Serviço solicitado"]') AS VARCHAR(30)) IN ('manutenção_instalação_serviço_solicitado', 'manutenção_reversa')
),
manutencao AS (
  SELECT
    DISTINCT
    id_house,
    plaquinha,
    ressalva,
    tem_plaquinha_flg,
    condo_nao_permite_flg,
    tipo_manutencao,
    dt_manutencao,
    CASE
      WHEN tem_plaquinha_flg = 1 THEN dt_manutencao
      ELSE NULL
    END AS dt_manutencao_sucesso,
    CASE
      WHEN tem_plaquinha_flg = 0 THEN dt_manutencao
      ELSE NULL
    END AS dt_manutencao_sem_sucesso,
    ROW_NUMBER() OVER(PARTITION BY id_house, tem_plaquinha_flg, dt_manutencao ORDER BY dt_manutencao DESC, condo_nao_permite_flg DESC) AS rn
  FROM
    manutencao_aux
  WHERE
    id_house > 1 -- and dt_manutencao >= (CURRENT_DATE - INTERVAL '2' year) --
),
datas AS (
  SELECT
    dt_ongoing_listing,
    o.id_house,
    id_condo,
    MAX(i.dt_install_sucesso) AS max_dt_install,
    MAX(i.dt_install_sem_sucesso) AS max_dt_sem_install,
    MIN(m.dt_manutencao_sucesso) AS min_dt_manutencao,
    MAX(m.dt_manutencao_sucesso) AS max_dt_manutencao,
    MAX(m.dt_manutencao_sem_sucesso) AS max_dt_sem_manutencao,
    COUNT(m.dt_manutencao) AS qtd_manutencoes
  FROM
    ol AS o
    LEFT JOIN
      installs AS i
          ON o.id_house = i.id_house
        AND o.dt_ongoing_listing >= i.dt_install
    LEFT JOIN
      manutencao AS m
        ON o.id_house = m.id_house
        AND o.dt_ongoing_listing >= m.dt_manutencao
  WHERE
    dt_ongoing_listing >= (CURRENT_DATE - INTERVAL '2' year) -- DATE('2023-01-01')
  GROUP BY 1,2,3
),
detalhes AS (
  SELECT
    dt_ongoing_listing,
    d.id_house,
    id_condo,
    max_dt_install,
    i.tipo_install,
    max_dt_sem_install,
    iss.ressalva AS ressalva_sem_install,
    iss.condo_nao_permite_flg AS condo_proibe_sem_install,
    min_dt_manutencao,
    max_dt_manutencao,
    max_dt_sem_manutencao,
    m.ressalva AS ressalva_sem_manutencao,
    m.condo_nao_permite_flg AS condo_proibe_sem_manutencao,
    qtd_manutencoes
  FROM datas AS d
    LEFT JOIN
      installs AS i
        ON d.id_house = i.id_house
        AND d.max_dt_install = i.dt_install_sucesso
    LEFT JOIN
      installs AS iss
        ON d.id_house = iss.id_house
        AND d.max_dt_sem_install = iss.dt_install_sem_sucesso
    LEFT JOIN
      manutencao AS m
        ON d.id_house = m.id_house
        AND d.max_dt_sem_manutencao = m.dt_manutencao_sem_sucesso
        AND m.rn = 1
),
condo_aux AS (
  SELECT
    dt_ongoing_listing,
    id_condo,
    MAX(max_dt_install) AS condo_max_dt_install,
    MAX(max_dt_sem_install) AS condo_max_dt_sem_install,
    MAX(max_dt_manutencao) AS condo_max_dt_manutencao,
    MAX(max_dt_sem_manutencao) AS condo_max_dt_sem_manutencao
  FROM
    detalhes
  GROUP BY 1,2
),
condo AS (
  SELECT
    c.dt_ongoing_listing,
    c.id_condo,
    condo_max_dt_install,
    condo_max_dt_sem_install,
    condo_max_dt_manutencao,
    condo_max_dt_sem_manutencao,
    MAX(di.condo_proibe_sem_install) AS condo_max_proibe_sem_install,
    MAX(dm.condo_proibe_sem_manutencao) AS condo_max_proibe_sem_manutencao
  FROM
    condo_aux AS c
    LEFT JOIN
      detalhes AS di
        ON c.id_condo = di.id_condo
        AND c.dt_ongoing_listing = di.dt_ongoing_listing
        AND c.condo_max_dt_sem_install = di.max_dt_sem_install
    LEFT JOIN
      detalhes AS dm
        ON c.id_condo = dm.id_condo
        AND c.dt_ongoing_listing = dm.dt_ongoing_listing
        AND c.condo_max_dt_sem_manutencao = dm.max_dt_sem_manutencao
  GROUP BY 1,2,3,4,5,6
),
cover AS (
  SELECT
    DISTINCT
    o.dt_ongoing_listing,
    o.id_house,
    d.id_condo,
    o.weekday_name,
    o.month_end,
    o.business_context,
    o.country_code,
    o.city_group,
    o.city_name,
    o.neighborhood,
    o.type AS listing_type,
    CASE
      WHEN (COALESCE(max_dt_install, '1900-01-01') > COALESCE(max_dt_sem_install, '1900-01-01'))
            AND (COALESCE(max_dt_install, '1900-01-01') > COALESCE(max_dt_manutencao, '1900-01-01'))
            AND (COALESCE(max_dt_install, '1900-01-01') > COALESCE(max_dt_sem_manutencao, '1900-01-01'))
        AND ((COALESCE(condo_max_dt_install, '1900-01-01') > COALESCE(condo_max_dt_sem_install, '1900-01-01'))
            AND (COALESCE(condo_max_dt_install, '1900-01-01') > COALESCE(condo_max_dt_manutencao, '1900-01-01'))
            AND (COALESCE(condo_max_dt_install, '1900-01-01') > COALESCE(condo_max_dt_sem_manutencao, '1900-01-01'))
        OR (COALESCE(condo_max_dt_manutencao, '1900-01-01') > COALESCE(condo_max_dt_install, '1900-01-01'))
            AND (COALESCE(condo_max_dt_manutencao, '1900-01-01') > COALESCE(condo_max_dt_sem_install, '1900-01-01'))
            AND (COALESCE(condo_max_dt_manutencao, '1900-01-01') > COALESCE(condo_max_dt_sem_manutencao, '1900-01-01')))
        THEN 'com placa'
      WHEN (COALESCE(max_dt_manutencao, '1900-01-01') > COALESCE(max_dt_install, '1900-01-01'))
            AND (COALESCE(max_dt_manutencao, '1900-01-01') > COALESCE(max_dt_sem_install, '1900-01-01'))
            AND (COALESCE(max_dt_manutencao, '1900-01-01') > COALESCE(max_dt_sem_manutencao, '1900-01-01'))
        AND ((COALESCE(condo_max_dt_install, '1900-01-01') > COALESCE(condo_max_dt_sem_install, '1900-01-01'))
            AND (COALESCE(condo_max_dt_install, '1900-01-01') > COALESCE(condo_max_dt_manutencao, '1900-01-01'))
            AND (COALESCE(condo_max_dt_install, '1900-01-01') > COALESCE(condo_max_dt_sem_manutencao, '1900-01-01'))
        OR (COALESCE(condo_max_dt_manutencao, '1900-01-01') > COALESCE(condo_max_dt_install, '1900-01-01'))
            AND (COALESCE(condo_max_dt_manutencao, '1900-01-01') > COALESCE(condo_max_dt_sem_install, '1900-01-01'))
            AND (COALESCE(condo_max_dt_manutencao, '1900-01-01') > COALESCE(condo_max_dt_sem_manutencao, '1900-01-01')))
        THEN 'com placa'
      ELSE 'sem placa'
    END AS placa_unica,
    CASE
      WHEN (COALESCE(condo_max_dt_install, '1900-01-01') > COALESCE(condo_max_dt_sem_install, '1900-01-01'))
            AND (COALESCE(condo_max_dt_install, '1900-01-01') > COALESCE(condo_max_dt_manutencao, '1900-01-01'))
            AND (COALESCE(condo_max_dt_install, '1900-01-01') > COALESCE(condo_max_dt_sem_manutencao, '1900-01-01'))
        THEN 'com placa'
      WHEN (COALESCE(condo_max_dt_manutencao, '1900-01-01') > COALESCE(condo_max_dt_install, '1900-01-01'))
            AND (COALESCE(condo_max_dt_manutencao, '1900-01-01') > COALESCE(condo_max_dt_sem_install, '1900-01-01'))
            AND (COALESCE(condo_max_dt_manutencao, '1900-01-01') > COALESCE(condo_max_dt_sem_manutencao, '1900-01-01'))
        THEN 'com placa'
      ELSE 'sem placa'
    END AS imovel_coberto,
    CASE
      WHEN condo_max_dt_install IS NULL AND condo_max_dt_sem_install IS NULL AND condo_max_dt_manutencao IS NULL AND condo_max_dt_sem_manutencao IS NULL THEN 0
      WHEN (COALESCE(condo_max_dt_install, '1900-01-01') > COALESCE(condo_max_dt_sem_install, '1900-01-01'))
            AND (COALESCE(condo_max_dt_install, '1900-01-01') > COALESCE(condo_max_dt_manutencao, '1900-01-01'))
            AND (COALESCE(condo_max_dt_install, '1900-01-01') > COALESCE(condo_max_dt_sem_manutencao, '1900-01-01'))
        THEN 0
      WHEN (COALESCE(condo_max_dt_sem_install, '1900-01-01') > COALESCE(condo_max_dt_install, '1900-01-01'))
            AND (COALESCE(condo_max_dt_sem_install, '1900-01-01') > COALESCE(condo_max_dt_manutencao, '1900-01-01'))
            AND (COALESCE(condo_max_dt_sem_install, '1900-01-01') > COALESCE(condo_max_dt_sem_manutencao, '1900-01-01'))
        THEN condo_max_proibe_sem_install
      WHEN (COALESCE(condo_max_dt_manutencao, '1900-01-01') > COALESCE(condo_max_dt_install, '1900-01-01'))
            AND (COALESCE(condo_max_dt_manutencao, '1900-01-01') > COALESCE(condo_max_dt_sem_install, '1900-01-01'))
            AND (COALESCE(condo_max_dt_manutencao, '1900-01-01') > COALESCE(condo_max_dt_sem_manutencao, '1900-01-01'))
        THEN 0
      WHEN (COALESCE(condo_max_dt_sem_manutencao, '1900-01-01') > COALESCE(condo_max_dt_install, '1900-01-01'))
            AND (COALESCE(condo_max_dt_sem_manutencao, '1900-01-01') > COALESCE(condo_max_dt_sem_install, '1900-01-01'))
            AND (COALESCE(condo_max_dt_sem_manutencao, '1900-01-01') > COALESCE(condo_max_dt_manutencao, '1900-01-01'))
        THEN condo_max_proibe_sem_manutencao
      ELSE 0
    END AS install_not_allowed,
    max_dt_install AS dt_install,
    tipo_install AS agent_install,
    ressalva_sem_install AS not_install_reason,
    min_dt_manutencao AS first_maintenance,
    CASE
      WHEN max_dt_manutencao IS NULL AND max_dt_sem_manutencao IS NULL THEN NULL
      WHEN (COALESCE(max_dt_manutencao, '1900-01-01') > COALESCE(max_dt_sem_manutencao, '1900-01-01')) THEN max_dt_manutencao
      WHEN (COALESCE(max_dt_manutencao, '1900-01-01') < COALESCE(max_dt_sem_manutencao, '1900-01-01')) THEN max_dt_sem_manutencao
      ELSE NULL
    END AS last_maintenance,
    CASE
      -- WHEN max_dt_manutencao IS NULL AND max_dt_sem_manutencao IS NULL THEN NULL
      WHEN (COALESCE(max_dt_manutencao, '1900-01-01') > COALESCE(max_dt_sem_manutencao, '1900-01-01'))
            AND LOWER(o.business_context) = 'rent'
            AND DATEDIFF(current_date, max_dt_manutencao) >= 30
        THEN TRUE -- com manutenção
      WHEN (COALESCE(max_dt_manutencao, '1900-01-01') > COALESCE(max_dt_sem_manutencao, '1900-01-01'))
            AND LOWER(o.business_context) = 'sale'
            AND DATEDIFF(current_date, max_dt_manutencao) >= 90
        THEN TRUE -- com manutenção
      WHEN (COALESCE(max_dt_manutencao, '1900-01-01') < COALESCE(max_dt_sem_manutencao, '1900-01-01'))
            AND LOWER(o.business_context) = 'rent'
            AND DATEDIFF(current_date, max_dt_sem_manutencao) >= 30
        THEN TRUE -- com manutenção
      WHEN (COALESCE(max_dt_manutencao, '1900-01-01') < COALESCE(max_dt_sem_manutencao, '1900-01-01'))
            AND LOWER(o.business_context) = 'sale'
            AND DATEDIFF(current_date, max_dt_sem_manutencao) >= 90
        THEN TRUE -- com manutenção
      WHEN (COALESCE(max_dt_install, '1900-01-01') > COALESCE(max_dt_sem_install, '1900-01-01'))
              AND (COALESCE(max_dt_install, '1900-01-01') > COALESCE(max_dt_manutencao, '1900-01-01'))
              AND (COALESCE(max_dt_install, '1900-01-01') > COALESCE(max_dt_sem_manutencao, '1900-01-01'))
          AND ((COALESCE(condo_max_dt_install, '1900-01-01') > COALESCE(condo_max_dt_sem_install, '1900-01-01'))
              AND (COALESCE(condo_max_dt_install, '1900-01-01') > COALESCE(condo_max_dt_manutencao, '1900-01-01'))
              AND (COALESCE(condo_max_dt_install, '1900-01-01') > COALESCE(condo_max_dt_sem_manutencao, '1900-01-01'))
          OR (COALESCE(condo_max_dt_manutencao, '1900-01-01') > COALESCE(condo_max_dt_install, '1900-01-01'))
              AND (COALESCE(condo_max_dt_manutencao, '1900-01-01') > COALESCE(condo_max_dt_sem_install, '1900-01-01'))
              AND (COALESCE(condo_max_dt_manutencao, '1900-01-01') > COALESCE(condo_max_dt_sem_manutencao, '1900-01-01')))
          AND max_dt_manutencao IS NULL AND max_dt_sem_manutencao IS NULL
          AND LOWER(o.business_context) = 'rent'
          AND DATEDIFF(current_date, max_dt_install) >= 30
        THEN TRUE -- com instalação e sem manutenção
      WHEN (COALESCE(max_dt_install, '1900-01-01') > COALESCE(max_dt_sem_install, '1900-01-01'))
              AND (COALESCE(max_dt_install, '1900-01-01') > COALESCE(max_dt_manutencao, '1900-01-01'))
              AND (COALESCE(max_dt_install, '1900-01-01') > COALESCE(max_dt_sem_manutencao, '1900-01-01'))
          AND ((COALESCE(condo_max_dt_install, '1900-01-01') > COALESCE(condo_max_dt_sem_install, '1900-01-01'))
              AND (COALESCE(condo_max_dt_install, '1900-01-01') > COALESCE(condo_max_dt_manutencao, '1900-01-01'))
              AND (COALESCE(condo_max_dt_install, '1900-01-01') > COALESCE(condo_max_dt_sem_manutencao, '1900-01-01'))
          OR (COALESCE(condo_max_dt_manutencao, '1900-01-01') > COALESCE(condo_max_dt_install, '1900-01-01'))
              AND (COALESCE(condo_max_dt_manutencao, '1900-01-01') > COALESCE(condo_max_dt_sem_install, '1900-01-01'))
              AND (COALESCE(condo_max_dt_manutencao, '1900-01-01') > COALESCE(condo_max_dt_sem_manutencao, '1900-01-01')))
          AND max_dt_manutencao IS NULL AND max_dt_sem_manutencao IS NULL
          AND LOWER(o.business_context) = 'sale'
          AND DATEDIFF(current_date, max_dt_install) >= 90
        THEN TRUE -- com instalação e sem manutenção
      WHEN (COALESCE(max_dt_manutencao, '1900-01-01') > COALESCE(max_dt_install, '1900-01-01'))
              AND (COALESCE(max_dt_manutencao, '1900-01-01') > COALESCE(max_dt_sem_install, '1900-01-01'))
              AND (COALESCE(max_dt_manutencao, '1900-01-01') > COALESCE(max_dt_sem_manutencao, '1900-01-01'))
          AND ((COALESCE(condo_max_dt_install, '1900-01-01') > COALESCE(condo_max_dt_sem_install, '1900-01-01'))
              AND (COALESCE(condo_max_dt_install, '1900-01-01') > COALESCE(condo_max_dt_manutencao, '1900-01-01'))
              AND (COALESCE(condo_max_dt_install, '1900-01-01') > COALESCE(condo_max_dt_sem_manutencao, '1900-01-01'))
          OR (COALESCE(condo_max_dt_manutencao, '1900-01-01') > COALESCE(condo_max_dt_install, '1900-01-01'))
              AND (COALESCE(condo_max_dt_manutencao, '1900-01-01') > COALESCE(condo_max_dt_sem_install, '1900-01-01'))
              AND (COALESCE(condo_max_dt_manutencao, '1900-01-01') > COALESCE(condo_max_dt_sem_manutencao, '1900-01-01')))
          AND max_dt_manutencao IS NULL AND max_dt_sem_manutencao IS NULL
          AND LOWER(o.business_context) = 'rent'
          AND DATEDIFF(current_date, max_dt_manutencao) >= 30
        THEN TRUE -- com instalação e sem manutenção
      WHEN (COALESCE(max_dt_manutencao, '1900-01-01') > COALESCE(max_dt_install, '1900-01-01'))
              AND (COALESCE(max_dt_manutencao, '1900-01-01') > COALESCE(max_dt_sem_install, '1900-01-01'))
              AND (COALESCE(max_dt_manutencao, '1900-01-01') > COALESCE(max_dt_sem_manutencao, '1900-01-01'))
          AND ((COALESCE(condo_max_dt_install, '1900-01-01') > COALESCE(condo_max_dt_sem_install, '1900-01-01'))
              AND (COALESCE(condo_max_dt_install, '1900-01-01') > COALESCE(condo_max_dt_manutencao, '1900-01-01'))
              AND (COALESCE(condo_max_dt_install, '1900-01-01') > COALESCE(condo_max_dt_sem_manutencao, '1900-01-01'))
          OR (COALESCE(condo_max_dt_manutencao, '1900-01-01') > COALESCE(condo_max_dt_install, '1900-01-01'))
              AND (COALESCE(condo_max_dt_manutencao, '1900-01-01') > COALESCE(condo_max_dt_sem_install, '1900-01-01'))
              AND (COALESCE(condo_max_dt_manutencao, '1900-01-01') > COALESCE(condo_max_dt_sem_manutencao, '1900-01-01')))
          AND max_dt_manutencao IS NULL AND max_dt_sem_manutencao IS NULL
          AND LOWER(o.business_context) = 'sale'
          AND DATEDIFF(current_date, max_dt_manutencao) >= 90
        THEN TRUE -- com instalação e sem manutenção
      ELSE NULL
    END AS is_ready_for_maintenance,
    ressalva_sem_manutencao AS not_maintenance_reason,
    qtd_manutencoes AS total_maintenances,
    CAST(NULL AS DOUBLE) AS new_installed_plaquinhas_target,
    CAST(NULL AS DOUBLE) AS active_plaquinhas_target,
    CAST(NULL AS DOUBLE) AS cover_target,
    CAST(NULL AS STRING) AS timeframe
  FROM
    ol_detalhes AS o
    LEFT JOIN
      detalhes AS d
        ON o.id_house = d.id_house
        AND o.dt_ongoing_listing = d.dt_ongoing_listing
    LEFT JOIN
      condo AS c
        ON d.id_condo = c.id_condo
        AND d.dt_ongoing_listing = c.dt_ongoing_listing
),
targets AS (
  -------------------------------------
  -- New installed plaquinhas target --
  -------------------------------------
  SELECT
    NULL AS dt_ongoing_listing,
    NULL AS id_house,
    NULL AS id_condo,
    NULL AS weekday_name,
    NULL AS month_end,
    business_context,
    'BR' AS country_code,
    city_group,
    NULL AS city_name,
    NULL AS neighborhood,
    listing_type,
    NULL AS placa_unica,
    NULL AS imovel_coberto,
    NULL AS install_not_allowed,
    CAST(dt_target AS DATE) AS dt_install,
    NULL AS agent_install,
    NULL AS not_install_reason,
    NULL AS first_maintenance,
    NULL AS last_maintenance,
    NULL AS is_ready_for_maintenance,
    NULL AS not_maintenance_reason,
    NULL AS total_maintenances,
    CAST(tgt.new_installed_plaquinhas_target AS DOUBLE) AS new_installed_plaquinhas_target,
    CAST(NULL AS DOUBLE) AS active_plaquinhas_target,
    CAST(NULL AS DOUBLE) AS cover_target,
    CAST(NULL AS STRING) AS timeframe
  FROM
    datalake_gsheets_clean.plaquinhas_installation_targets AS tgt
  UNION ALL
    --------------------------------------
    -- Active plaquinhas & Cover target --
    --------------------------------------
  SELECT
    dt_target AS dt_ongoing_listing,
    NULL AS id_house,
    NULL AS id_condo,
    NULL AS weekday_name,
    NULL AS month_end,
    business_context,
    'BR' AS country_code,
    city_group,
    NULL AS city_name,
    NULL AS neighborhood,
    NULL AS listing_type,
    NULL AS placa_unica,
    NULL AS imovel_coberto,
    NULL AS install_not_allowed,
    CAST(NULL AS DATE) AS dt_install,
    NULL AS agent_install,
    NULL AS not_install_reason,
    NULL AS first_maintenance,
    NULL AS last_maintenance,
    NULL AS is_ready_for_maintenance,
    NULL AS not_maintenance_reason,
    NULL AS total_maintenances,
    CAST(NULL AS DOUBLE) AS new_installed_plaquinhas_target,
    CAST(tgt.active_plaquinhas_target AS DOUBLE) AS active_plaquinhas_target,
    CAST(tgt.cover_target AS DOUBLE) AS cover_target,
    timeframe
  FROM
    datalake_gsheets_clean.plaquinhas_cover_targets AS tgt
) --------------------------------------------
-- UNION Cover, New installed and targets --
--------------------------------------------
SELECT
  *
FROM
  cover
UNION ALL
SELECT
  *
FROM
  targets
