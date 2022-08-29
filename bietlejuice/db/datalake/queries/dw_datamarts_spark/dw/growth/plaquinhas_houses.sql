WITH
houses_w_plaquinhas AS (
---------------------------------------------------------
-- Plaquinhas installed by owners, agencies and/or b2b --
---------------------------------------------------------
    SELECT
        p.id_house::BIGINT AS id_house,
        dt_plaquinha::DATE AS dt_plaquinha,
        installation_type,
        listing_type
    FROM
        datalake_gsheets_clean.branding_where_is_plaquinha p
    GROUP BY
        1,2,3,4
    UNION
-------------------------------------------
-- Plaquinhas installed by photographers --
-------------------------------------------
    SELECT
        gsps.id_house::BIGINT AS id_house,
        dpj.dt_photos_uploaded::DATE AS dt_plaquinha,
        'Photographer' AS installation_type,
        'New Listing' AS listing_type
    FROM
        datalake_gsheets_clean.aux_check_photo_sender gsps
    LEFT JOIN dw_public.dim_photo_job dpj
        ON dpj.sk_photo_job = gsps.id_photo_job
    WHERE
        gsps.sign_placement <> ''
    GROUP BY
        1,2,3,4
),
condo_w_plaquinhas_rent AS (
    SELECT
        f.sk_condo,
        hp.dt_plaquinha,
        hp.installation_type,
        hp.listing_type
    FROM
        houses_w_plaquinhas hp
    JOIN dw_public.dim_house_listing dhl
        ON hp.id_house = dhl.id_house
    JOIN dw_public.fact_house_listing_flows f
        ON f.sk_house_listing = dhl.sk_house_listing
    WHERE 
        f.sk_condo > 0
    GROUP BY 
        1,2,3,4
),
daily_published_listings_rent AS (
----------------------------
-- Ongoing listings query --
----------------------------
    SELECT  /*+ RANGE_JOIN(f, 19000) */
        f.sk_house_listing,
        f.status_history,
        d.date,
        d.week_start,
        d.weekday_name,
        d.month_start,
        d.month_end,
        ROW_NUMBER() OVER(PARTITION BY f.sk_house_listing, d.date ORDER BY f.ts_status_start DESC NULLS FIRST) AS order_status -- daily order status
    FROM
        dw_public.fact_house_listing_status f
    JOIN dw_public.dim_date d 
        ON d.sk_date BETWEEN NULLIF(f.sk_status_start_date,-1) AND COALESCE(DATE_FORMAT(TO_DATE(NULLIF(sk_status_end_date, -1)::STRING, 'yyyyMMdd') - INTERVAL '1' day, 'yyyyMMdd')::BIGINT, DATE_FORMAT(CURRENT_DATE - INTERVAL '1' day, 'yyyyMMdd'))::BIGINT
    WHERE
        f.status_history = 'publicado' -- consider only published status
        AND SUBSTRING(sk_house_listing,10,12) <> '000' -- consider only listings that already started publication
        AND date >= DATE('2021-02-01') -- Month when the campaign started 
),
plaquinhas_rent AS (
    ----------------------------------------
    -- Joining OL and plaquinhas FR infos --
    ----------------------------------------
    SELECT 
        fhs.sk_house_listing,
        fhs.date,
        fhs.week_start,
        fhs.weekday_name,
        fhs.month_start,
        fhs.month_end,
        fhs.order_status,
        fhs.status_history,
        fhl.sk_region,
        COALESCE(hp.dt_plaquinha,cp.dt_plaquinha) AS dt_plaquinha,
        COALESCE(hp.id_house,cp.sk_condo) AS id_plaquinha,
        hp.dt_plaquinha AS dt_plaquinha_house,
        hp.id_house AS id_plaquinha_house,
        COALESCE(hp.installation_type,cp.installation_type) AS installation_type,
        COALESCE(hp.listing_type) AS listing_type
    FROM
        daily_published_listings_rent fhs
    LEFT JOIN dw_public.fact_house_listings fhl 
        ON fhs.sk_house_listing = fhl.sk_house_listing
    LEFT JOIN houses_w_plaquinhas hp
        ON (fhl.sk_house_listing/1000)::INTEGER = hp.id_house 
    LEFT JOIN condo_w_plaquinhas_rent cp
        ON fhl.sk_condo = cp.sk_condo
    WHERE
        fhs.order_status = 1
        AND fhl.sk_region > 0
),
plaquinhas_sale AS (
    WITH 
    condo_w_plaquinhas_sale AS (
        SELECT
            flf.sk_condo,
            hp.dt_plaquinha,
            hp.installation_type,
            hp.listing_type
        FROM
            houses_w_plaquinhas hp
        JOIN dw_sale.fact_listing_flows flf
            ON substring(flf.sk_house_listing,0,9) = hp.id_house
        WHERE 
            flf.sk_condo > 0
        GROUP BY 
            1,2,3,4
    ),
    daily_published_listings_sale AS (
    ----------------------------
    -- Ongoing listings query --
    ----------------------------
        SELECT  /*+ RANGE_JOIN(f, 19000) */
            f.sk_sale_listing AS sk_house_listing,
            f.status_history,
            d.date,
            d.week_start,
            d.weekday_name,
            d.month_start,
            d.month_end,
            ROW_NUMBER() OVER(PARTITION BY f.sk_sale_listing, d.date ORDER BY f.ts_status_started DESC) AS order_status -- daily order status
        FROM
            dw_sale.fact_listing_status f
        JOIN dw_public.dim_date d 
            ON d.sk_date BETWEEN NULLIF(f.sk_status_start_date,-1) AND COALESCE(DATE_FORMAT(TO_DATE(NULLIF(sk_status_end_date, -1)::STRING, 'yyyyMMdd') - INTERVAL '1' day, 'yyyyMMdd')::BIGINT, DATE_FORMAT(CURRENT_DATE - INTERVAL '1' day, 'yyyyMMdd')::BIGINT)
        WHERE
            f.status_history = 'PUBLISHED' -- consider only published status
            AND date >= DATE('2021-09-01') -- Month when the campaign started
    )
    ----------------------------------------
    -- Joining OL and plaquinhas FS infos --
    ----------------------------------------
    SELECT
        fhs.sk_house_listing,
        fhs.date,
        fhs.week_start,
        fhs.weekday_name,
        fhs.month_start,
        fhs.month_end,
        fhs.order_status,
        fhs.status_history,
        flf.sk_region,
        COALESCE(hp.dt_plaquinha,cps.dt_plaquinha) AS dt_plaquinha,
        COALESCE(hp.id_house,cps.sk_condo) AS id_plaquinha,
        hp.dt_plaquinha AS dt_plaquinha_house,
        hp.id_house AS id_plaquinha_house,
        COALESCE(hp.installation_type,cps.installation_type) AS installation_type,
        COALESCE(hp.listing_type) AS listing_type
    FROM
        daily_published_listings_sale fhs
    LEFT JOIN dw_sale.fact_listing_flows flf 
        ON substring(fhs.sk_house_listing,0,9) = substring(flf.sk_house_listing,0,9)
    LEFT JOIN houses_w_plaquinhas hp
        ON substring(fhs.sk_house_listing,0,9) = hp.id_house
    LEFT JOIN condo_w_plaquinhas_sale cps
        ON flf.sk_condo = cps.sk_condo
    WHERE
        fhs.order_status = 1
        AND flf.sk_region > 0
),
metrics_base AS (
    SELECT
        CAST(pr.sk_house_listing/1000 AS BIGINT) AS id_house,
        CAST('Rent' AS STRING) AS business_context,
        CAST(dr.short_region_name AS STRING) AS short_region_name,
        CAST(dr.city_group AS STRING) AS city_group,
        CAST(dr.city_name AS STRING) AS city_name,
        CAST(dr.name AS STRING) AS subregion_name,
        CAST(pr.installation_type AS STRING) AS installation_type,
        CAST(pr.listing_type AS STRING) AS listing_type,
        CAST(pr.weekday_name AS STRING) AS weekday_name,
        CAST(CASE
            WHEN pr.id_plaquinha IS NOT NULL 
                AND pr.dt_plaquinha <= pr.date THEN TRUE
            ELSE FALSE
        END AS BOOLEAN) AS has_plaquinha, -- flag to identify if the house or the house condo has plaquinha
        CAST(CASE
            WHEN pr.id_plaquinha_house IS NOT NULL 
                AND pr.dt_plaquinha_house <= pr.date THEN TRUE
            ELSE FALSE
        END AS BOOLEAN) AS has_plaquinha_house, -- flag to identify if the house has plaquinha
        CAST(pr.month_end AS DATE) AS dt_month_end,
        CAST(pr.date AS DATE) AS dt,
        CAST(pr.dt_plaquinha AS DATE) AS dt_plaquinha_installed,
        CAST(pr.dt_plaquinha_house AS DATE) AS dt_plaquinha_installed_house,
        CAST(NULL AS DOUBLE) AS new_installed_plaquinhas_target,
        CAST(NULL AS DOUBLE) AS active_plaquinhas_target,
        CAST(NULL AS DOUBLE) AS cover_percent_target
    FROM
        plaquinhas_rent pr
    LEFT JOIN dw_public.dim_region dr
        ON pr.sk_region = dr.sk_region
    GROUP BY 
        1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18
    UNION
    SELECT
        CAST(substring(ps.sk_house_listing,0,9) AS BIGINT) AS id_house,
        CAST('Sale' AS STRING) AS business_context,
        CAST(dr.short_region_name AS STRING) AS short_region_name,
        CAST(dr.city_group AS STRING) AS city_group,
        CAST(dr.city_name AS STRING) AS city_name,
        CAST(dr.name AS STRING) AS subregion_name,
        CAST(ps.installation_type AS STRING) AS installation_type,
        CAST(ps.listing_type AS STRING) AS listing_type,
        CAST(ps.weekday_name AS STRING) AS weekday_name,
        CAST(CASE
            WHEN ps.id_plaquinha IS NOT NULL 
                AND ps.dt_plaquinha <= ps.date THEN TRUE
            ELSE FALSE
        END AS BOOLEAN) AS has_plaquinha, -- flag to identify if the house or the house condo has plaquinha
        CAST(CASE
            WHEN ps.id_plaquinha_house IS NOT NULL 
                AND ps.dt_plaquinha_house <= ps.date THEN TRUE
            ELSE FALSE
        END AS BOOLEAN) AS has_plaquinha_house, -- flag to identify if the house has plaquinha
        CAST(ps.month_end AS DATE) AS dt_month_end,
        CAST(ps.date AS DATE) AS dt,
        CAST(ps.dt_plaquinha AS DATE) AS dt_plaquinha_installed,
        CAST(ps.dt_plaquinha_house AS DATE) AS dt_plaquinha_installed_house,
        CAST(NULL AS DOUBLE) AS new_installed_plaquinhas_target,
        CAST(NULL AS DOUBLE) AS active_plaquinhas_target,
        CAST(NULL AS DOUBLE) AS cover_percent_target
    FROM
        plaquinhas_sale ps
    LEFT JOIN dw_public.dim_region dr
        ON ps.sk_region = dr.sk_region
    GROUP BY 
        1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18
),
targets AS (
    -------------------------------------
    -- New installed plaquinhas target --
    -------------------------------------
    SELECT 
        CAST(NULL AS BIGINT) AS id_house,
        CAST(tgt.business_context AS STRING) AS business_context,
        CAST(NULL AS STRING) AS short_region_name,
        CAST(city_group AS STRING) AS city_group,
        CAST(NULL AS STRING) AS city_name,
        CAST(NULL AS STRING) AS subregion_name,
        CAST(NULL AS STRING) AS installation_type,
        CAST(listing_type AS STRING) AS listing_type,
        CAST(NULL AS STRING) AS weekday_name,
        CAST(NULL AS BOOLEAN) AS has_plaquinha,
        CAST(NULL AS BOOLEAN) AS has_plaquinha_house,
        CAST(NULL AS DATE) AS dt_month_end,
        CAST(NULL AS DATE) AS dt,
        CAST(NULL AS DATE) AS dt_plaquinha_installed,
        CAST(tgt.dt_target AS DATE) AS dt_plaquinha_installed_house,
        CAST(tgt.new_installed_plaquinhas_target AS DOUBLE) AS new_installed_plaquinhas_target,
        CAST(NULL AS DOUBLE) AS active_plaquinhas_target,
        CAST(NULL AS DOUBLE) AS cover_percent_target
    FROM 
        datalake_gsheets_clean.plaquinhas_installation_targets tgt
    UNION ALL 
    ------------------------------
    -- Active plaquinhas target --
    ------------------------------
    SELECT 
        CAST(NULL AS BIGINT) AS id_house,
        CAST(tgt.business_context AS STRING) AS business_context,
        CAST(NULL AS STRING) AS short_region_name,
        CAST(city_group AS STRING) AS city_group,
        CAST(NULL AS STRING) AS city_name,
        CAST(NULL AS STRING) AS subregion_name,
        CAST(NULL AS STRING) AS installation_type,
        CAST(listing_type AS STRING) AS listing_type,
        CAST(NULL AS STRING) AS weekday_name,
        CAST(NULL AS BOOLEAN) AS has_plaquinha,
        CAST(NULL AS BOOLEAN) AS has_plaquinha_house,
        CAST(NULL AS DATE) AS dt_month_end,
        CAST(tgt.dt_target AS DATE) AS dt,
        CAST(NULL AS DATE) AS dt_plaquinha_installed,
        CAST(NULL AS DATE) AS dt_plaquinha_installed_house,
        CAST(NULL AS DOUBLE) AS new_installed_plaquinhas_target,
        CAST(tgt.active_plaquinhas_target AS DOUBLE) AS active_plaquinhas_target,
        CAST(tgt.cover_percent_target AS DOUBLE) AS cover_percent_target
    FROM 
        datalake_gsheets_clean.plaquinhas_installation_targets tgt
)
-------------------------------
-- UNION metrics and targets --
-------------------------------
SELECT 
    mb.*
FROM 
    metrics_base mb
UNION ALL
SELECT 
    t.*
FROM 
    targets t