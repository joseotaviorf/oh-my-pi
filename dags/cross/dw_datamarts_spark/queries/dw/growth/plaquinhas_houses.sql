WITH  
----------------------------------------------------------------
-- CTE that make the Union between all Placas Install sources --
----------------------------------------------------------------
installs AS (
---------------------------------------------------
-- Histórico de instalações inputados no GSheets --
---------------------------------------------------
-- This installs info came from a legacy GSheets that was used during the beginnig of Placas operation.
-- It has info from 11/Feb/21 to 22/Nov/22.
-- After that, inputs came from different sources.
---------------------------------------------------
  SELECT DISTINCT
    id_house,
    id_house AS id_install,
    NULL AS photographer_id,
    DATE(dt_plaquinha) AS dt_install, 
    h.id_region AS sk_region,
    p.listing_type,
    NULL AS business_context,
    p.installation_type AS agent_install,
    NULL AS not_install_reason,
    TRUE AS has_plaquinha
  FROM 
    datalake_gsheets_clean.branding_where_is_plaquinha AS p
  LEFT JOIN 
    datalake_ebdb_clean.house AS h
      ON h.id = p.id_house
  UNION ALL
-----------------------------
-- First Listings Installs --
---------------------------------------------------
-- This installs info came from a table from quality team that inform if the Photographer Job was done by installing a Placa too.
-- Until the construction of this quey, Photographer is the only agent that install Placas into First Listings.
-- Therefore, all Photo Job is a opportunity to install Placas. Placas Operation team has interest to measure this conversion between Photo Jobs and Placas Installs
---------------------------------------------------
  SELECT DISTINCT
    dhl.id_house,
    dpj.sk_photo_job AS id_install,
    dpj.photographer_id,
    DATE(FROM_UTC_TIMESTAMP(dpj.dt_photos_uploaded,'America/Sao_Paulo')) AS dt_install, 
    fpj.sk_region, 
    'First Listings' AS listing_type,
    CASE 
      WHEN dhl.is_for_rent = TRUE AND dhl.is_for_sale = FALSE THEN 'Rent'
      WHEN dhl.is_for_rent = FALSE AND dhl.is_for_sale = TRUE THEN 'Sale'
      WHEN dhl.is_for_rent = TRUE AND dhl.is_for_sale = TRUE THEN 'Hibrido'
      WHEN dhl.is_for_rent = FALSE AND dhl.is_for_sale = FALSE THEN 'None'
    END AS business_context,
    'Photographer' AS agent_install,
    NULL AS not_install_reason,
    CASE 
      WHEN gsps.id_house IS NOT NULL THEN TRUE
      ELSE FALSE
    END AS has_plaquinha
  FROM 
    dw_public.fact_photo_job AS fpj 
  LEFT JOIN 
    dw_public.dim_photo_job AS dpj 
      ON dpj.sk_photo_job = fpj.id_photo_job
  LEFT JOIN 
    dw_public.dim_house_listing AS dhl
      ON CAST((fpj.sk_house_listing/1000) AS BIGINT) = dhl.id_house
  LEFT JOIN 
    datalake_listing_jobs.listing_quality_tasks AS gsps
      ON gsps.id_house = dhl.id_house 
      AND gsps.signboard_location <> ''
  WHERE 
    (is_for_rent IS NOT NULL
    AND is_for_sale IS NOT NULL)
    AND fpj.sk_region > 0 
  UNION ALL
-----------------------------------------
-- Ongoing Listings Installs - Motoboy --
---------------------------------------------------
-- This installs info came from a table from zendesk. 
-- Partners companies as Promove and Malote made Placas installs on Ongoing Listings through Motoboy operation.
-- Theses partners fill zendesk forms to input these infos.
---------------------------------------------------
  SELECT DISTINCT
    CAST(GET_JSON_OBJECT(dt.custom_fields, '$["[SO] Código do Imóvel"]') AS BIGINT) AS id_house,
    CAST(GET_JSON_OBJECT(dt.custom_fields, '$["[SO] Código do Imóvel"]') AS BIGINT) AS id_install,  
    NULL AS photographer_id,   
    CAST(GET_JSON_OBJECT(dt.custom_fields, '$["[SO] Data de instalação"]') AS VARCHAR(20)) AS dt_install,
    h.id_region AS sk_region,
    'Ongoing Listings' AS listing_type, 
    CASE
      WHEN CAST(GET_JSON_OBJECT(dt.custom_fields, '$["[SO] Tipo de anúncio "]') AS VARCHAR(20)) like '%sale%' THEN 'Sale'
      WHEN CAST(GET_JSON_OBJECT(dt.custom_fields, '$["[SO] Tipo de anúncio "]') AS VARCHAR(20)) like '%rent%' THEN 'Rent'
      WHEN CAST(GET_JSON_OBJECT(dt.custom_fields, '$["[SO] Tipo de anúncio "]') AS VARCHAR(20)) like '%híbrido%' THEN 'Hibrido'
    END AS business_context,
    CASE
      WHEN CAST(GET_JSON_OBJECT(dt.custom_fields, '$["[SO] Agente Instalação"]') AS VARCHAR(40)) = 'promove_agente_instalação' THEN 'Promove'
      WHEN CAST(GET_JSON_OBJECT(dt.custom_fields, '$["[SO] Agente Instalação"]') AS VARCHAR(40)) = 'motoboy_express_agente_instalação' THEN 'Malote'
    END AS agent_install,
    CAST(GET_JSON_OBJECT(dt.custom_fields, '$["[SO] Motivo "]') AS VARCHAR(100)) AS not_install_reason,
    CASE
      WHEN  CAST(GET_JSON_OBJECT(dt.custom_fields, '$["[SO] Instalação realizada"]') AS VARCHAR(30)) = 'não_instalação_realizada' THEN FALSE
      ELSE TRUE
    END AS has_plaquinha
  FROM 
    dw_tickets.dim_ticket AS dt
  LEFT JOIN 
    datalake_ebdb_clean.house AS h
      ON h.id = CAST(GET_JSON_OBJECT(custom_fields, '$["[SO] Código do Imóvel"]') AS BIGINT)
  WHERE 
    dt.group_name = 'Plaquinhas - Pedidos da FAQ [SO]'
    AND dt.subject LIKE '%Instalação%' 
    AND FROM_UTC_TIMESTAMP(CAST(dt.ts_created  AS TIMESTAMP), 'America/Sao_Paulo') >= DATE (DATE '2023-01-17')
    AND h.id_region > 0
  UNION ALL   
---------------------------------------------
-- Ongoing Listings Installs - PP Organico --
---------------------------------------------------
-- This installs info came from a GSheets that is used as database from a form acessed by PP. 
-- The PP is able to require its own Placa to make its install. When it happens, one line iss filled on GSheets and used to compute this info.
---------------------------------------------------
  SELECT DISTINCT
    p.id_house,
    p.id_ticket AS id_install,
    NULL AS photographer_id,
    p.dt_install, 
    h.id_region AS sk_region,
    "Ongoing Listings" AS listing_type, 
    CASE 
      WHEN business_context = 'Aluguel' THEN 'Rent'
      WHEN business_context = 'Venda' THEN 'Sale'
      WHEN business_context = 'Aluguel+Venda' THEN 'Hibrido'
    END AS business_context, 
    "PP Organic" AS agent_install,
    NULL AS not_install_reason, 
    TRUE AS has_plaquinha
  FROM 
      datalake_gsheets_clean.plaquinhas_installation_pp_organic AS p 
  LEFT JOIN 
    datalake_ebdb_clean.house AS h
      ON h.id = p.id_house
  WHERE 
    client_type = "Proprietário"
),
---------------------------------------------------------------------------
-- CTEs that identify condos that we had houses with placas installed at --
--------------------------------------------------------------------------_
condo_with_plaquinhas_rent AS ( 
  SELECT DISTINCT
      i.dt_install,
      i.sk_region, 
      i.listing_type,
      i.business_context, 
      i.agent_install,
      i.has_plaquinha, 
      i.id_house,
      f.sk_condo,
      i.id_install
  FROM 
    installs AS i
  INNER JOIN 
    datalake_listing_temp.dim_house_listing_house AS dhl
      ON i.id_house = dhl.id_house
  INNER JOIN 
    dw_public.fact_house_listing_flows AS f
      ON f.sk_house_listing = dhl.sk_house_listing
  WHERE
    f.sk_condo > 0
),
condo_with_plaquinhas_sale AS ( 
  SELECT DISTINCT
    i.dt_install,
    i.sk_region, 
    i.listing_type,
    i.business_context, 
    i.agent_install,
    i.has_plaquinha, 
    i.id_house,
    f.sk_condo,
    i.id_install
  FROM 
    installs AS i
  INNER JOIN 
    dw_sale.fact_listing_flows AS f
      ON substring(f.sk_house_listing,0,9) = i.id_house
  WHERE
    f.sk_condo > 0
),
rent_ongoing_listings AS (
----------------------------
-- Rent Ongoing Listings --
----------------------------
  SELECT  /*+ RANGE_JOIN(f, 19000) */
    f.sk_house_listing,
    f.status_history,
    f.sk_region,
    d.date,
    d.weekday_name,
    d.month_start,
    d.month_end,
    ROW_NUMBER() OVER(PARTITION BY f.sk_house_listing, d.date ORDER BY f.ts_status_start DESC NULLS FIRST) AS order_status -- daily order status
  FROM
    datalake_listing_temp.fact_house_listing_status_house AS f
  JOIN 
    dw_public.dim_date AS d
      ON d.sk_date BETWEEN NULLIF(f.sk_status_start_date,-1) AND COALESCE(DATE_FORMAT(TO_DATE(NULLIF(sk_status_end_date, -1)::STRING, 'yyyyMMdd') - INTERVAL '1' day, 'yyyyMMdd')::BIGINT, DATE_FORMAT(CURRENT_DATE - INTERVAL '1' day, 'yyyyMMdd'))::BIGINT
  WHERE
    f.status_history IN ('publicado', 'PUBLISHED') -- consider only published status
    AND SUBSTRING(sk_house_listing,10,12) <> '000' -- consider only listings that already started publication
    AND date >= DATE('2021-02-01') -- Month when the campaign started
),
sale_ongoing_listings AS (
----------------------------
-- Sale Ongoing Listings --
----------------------------
  SELECT  /*+ RANGE_JOIN(f, 19000) */
    f.sk_sale_listing AS sk_house_listing,
    f.status_history,
    f.sk_region,
    d.date,
    d.weekday_name,
    d.month_start,
    d.month_end,
    ROW_NUMBER() OVER(PARTITION BY f.sk_sale_listing, d.date ORDER BY f.ts_status_started DESC) AS order_status -- daily order status
  FROM
    dw_sale.fact_listing_status AS f
  JOIN 
    dw_public.dim_date AS d
      ON d.sk_date BETWEEN NULLIF(f.sk_status_start_date,-1) AND COALESCE(DATE_FORMAT(TO_DATE(NULLIF(sk_status_end_date, -1)::STRING, 'yyyyMMdd') - INTERVAL '1' day, 'yyyyMMdd')::BIGINT, DATE_FORMAT(CURRENT_DATE - INTERVAL '1' day, 'yyyyMMdd')::BIGINT)
  WHERE
    f.status_history IN ('publicado', 'PUBLISHED') -- consider only published status
    AND date >= DATE('2021-09-01') -- Month when the campaign started
),
cover_rent AS (
  ----------------------------------------
  -- Joining OL and plaquinhas FR infos --
  ----------------------------------------
  SELECT DISTINCT
    CAST(ol.sk_house_listing/1000 AS BIGINT) AS id_house,
    NULL AS id_install, 
    NULL AS photographer_id,
    TIMESTAMP(ol.date) AS dt_ongoing_listing,
    NULL AS dt_install,
    NULL AS timeframe,
    ol.weekday_name,
    ol.month_end,
    'Rent' AS business_context,
    dr.country_code,
    dr.city_group,
    dr.city_name,
    dr.name AS neighborhood,
    NULL AS agent_install,
    NULL AS listing_type,
    NULL AS not_install_reason, 
    CASE
        WHEN COALESCE(i.id_house, cp.sk_condo) IS NOT NULL THEN TRUE
        ELSE FALSE
    END AS has_plaquinha, -- flag to identify if the house/condo has plaquinha
    NULL AS new_installed_plaquinhas_target, 
    NULL AS active_plaquinhas_target,
    NULL AS cover_target
  FROM
    rent_ongoing_listings AS ol
  LEFT JOIN 
    datalake_listing_temp.fact_house_listings_house AS fhl
      ON ol.sk_house_listing = fhl.sk_house_listing
  LEFT JOIN 
    installs AS i
      ON CAST((fhl.sk_house_listing/1000) AS BIGINT) = i.id_house
      AND i.dt_install <= ol.date
      AND i.has_plaquinha = TRUE
  LEFT JOIN 
    condo_with_plaquinhas_rent AS cp
      ON fhl.sk_condo = cp.sk_condo
      AND cp.dt_install <= ol.date
      AND cp.has_plaquinha = TRUE
  LEFT JOIN 
    dw_public.dim_region AS dr
     ON ol.sk_region = dr.sk_region
  WHERE
    ol.order_status = 1
    AND ol.sk_region > 0
    AND dr.country_code = 'BR'
    AND dr.city_group NOT IN ('Belo Horizonte', 'Uberlândia')
),
cover_sale AS (
  ----------------------------------------
  -- Joining OL and plaquinhas FS infos --
  ----------------------------------------
  SELECT DISTINCT
    CAST(ol.sk_house_listing/1000 AS BIGINT) AS id_house,
    NULL AS id_install, 
    NULL AS photographer_id,
    TIMESTAMP(ol.date) AS dt_ongoing_listing,
    NULL AS dt_install,
    NULL AS timeframe,
    ol.weekday_name,
    ol.month_end,
    'Sale' AS business_context,
    dr.country_code,
    dr.city_group,
    dr.city_name,
    dr.name AS neighborhood,
    NULL AS agent_install,
    NULL AS listing_type,
    NULL AS not_install_reason, 
    CASE
        WHEN COALESCE(i.id_house, cp.sk_condo) IS NOT NULL THEN TRUE
        ELSE FALSE
    END AS has_plaquinha, -- flag to identify if the house/condo has plaquinha
    NULL AS new_installed_plaquinhas_target,
    NULL AS active_plaquinhas_target,
    NULL AS cover_target
  FROM 
    sale_ongoing_listings AS ol
  LEFT JOIN 
    dw_sale.fact_listing_flows AS flf
      ON SUBSTRING(ol.sk_house_listing,0,9) = SUBSTRING(flf.sk_house_listing,0,9)
  LEFT JOIN 
    installs AS i
      ON substring(ol.sk_house_listing,0,9) = i.id_house
      AND i.dt_install <= ol.date
      AND i.has_plaquinha = TRUE
  LEFT JOIN 
    condo_with_plaquinhas_sale AS cp
      ON flf.sk_condo = cp.sk_condo
      AND cp.dt_install <= ol.date
      AND cp.has_plaquinha = TRUE
  LEFT JOIN 
    dw_public.dim_region AS dr
      ON ol.sk_region = dr.sk_region
  WHERE
    ol.order_status = 1
    AND ol.sk_region > 0
    AND dr.country_code = 'BR'
    AND dr.city_group NOT IN ('Belo Horizonte', 'Uberlândia')
), 
new_installs AS (
  -------------------------------
  -- New Installed Placas info --
  -------------------------------
  SELECT
    NULL AS id_house, 
    id_install, 
    photographer_id,
    NULL AS dt_ongoing_listing,
    TIMESTAMP(i.dt_install) AS dt_install,
    NULL AS timeframe,
    NULL AS weekday_name,
    NULL AS month_end,
    business_context,
    dr.country_code,
    dr.city_group,
    dr.city_name,
    dr.name AS neighborhood,
    i.agent_install,
    i.listing_type,
    i.not_install_reason, 
    i.has_plaquinha,
    NULL AS new_installed_plaquinhas_target, 
    NULL AS active_plaquinhas_target,
    NULL AS cover_target
  FROM 
    installs AS i 
  LEFT JOIN 
    dw_public.dim_region AS dr 
      ON dr.sk_region = i.sk_region
  WHERE 
    (dr.country_code = 'BR' OR dr.country_code IS NULL)
    AND (dr.city_group NOT IN ('Belo Horizonte', 'Uberlândia') OR dr.city_group IS NULL)
),
targets AS (
  -------------------------------------
  -- New installed plaquinhas target --
  -------------------------------------
  SELECT
    NULL AS id_house, 
    NULL AS id_install,
    NULL AS photographer_id,
    NULL AS dt_ongoing_listing,
    TIMESTAMP(dt_target) as dt_install,
    NULL AS timeframe,
    NULL AS weekday_name,
    NULL AS month_end,
    business_context,
    'BR' AS country_code,
    city_group,
    NULL AS city_name,
    NULL AS neighborhood,
    NULL AS agent_install,
    listing_type,
    NULL AS not_install_reason, 
    NULL AS has_plaquinha,
    CAST(tgt.new_installed_plaquinhas_target AS DOUBLE) AS new_installed_plaquinhas_target, 
    NULL AS active_plaquinhas_target,
    NULL AS cover_target
  FROM 
    datalake_gsheets_clean.plaquinhas_installation_targets AS tgt
  UNION ALL
  --------------------------------------
  -- Active plaquinhas & Cover target --
  --------------------------------------
  SELECT
    NULL AS id_house,
    NULL AS id_install,
    NULL AS photographer_id, 
    TIMESTAMP(dt_target) AS dt_ongoing_listing,
    timeframe,
    NULL as dt_install,
    NULL AS weekday_name,
    NULL AS month_end,
    business_context,
    'BR' AS country_code,
    city_group,
    NULL AS city_name,
    NULL AS neighborhood,
    NULL AS agent_install,
    NULL AS listing_type,
    NULL AS not_install_reason, 
    NULL AS has_plaquinha,
    NULL AS new_installed_plaquinhas_target, 
    CAST(tgt.active_plaquinhas_target AS DOUBLE) AS active_plaquinhas_target,
    CAST(tgt.cover_target AS DOUBLE) AS cover_target
  FROM 
    datalake_gsheets_clean.plaquinhas_cover_targets AS tgt
)
--------------------------------------------
-- UNION Cover, New installed and targets --
--------------------------------------------
SELECT 
  * 
FROM 
    cover_rent
UNION ALL 
SELECT 
  * 
FROM 
    cover_sale 
UNION ALL 
SELECT 
  * 
FROM 
    new_installs
UNION ALL 
SELECT
  *
FROM 
    targets