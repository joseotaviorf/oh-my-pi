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
        datalake_gsheets_clean_prod.branding_where_is_plaquinha p
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
        datalake_gsheets_clean_prod.aux_check_photo_sender gsps
    LEFT JOIN dim_photo_job dpj
        ON dpj.sk_photo_job = gsps.id_photo_job
    WHERE
        gsps.sign_placement <> ''
    GROUP BY
        1,2,3,4
),
plaquinhas_rent AS (
    WITH 
    condo_w_plaquinhas_rent AS (
        SELECT
            f.sk_condo,
            hp.dt_plaquinha,
            hp.installation_type,
            hp.listing_type
        FROM
            houses_w_plaquinhas hp
        JOIN dim_house_listing dhl
            ON hp.id_house = dhl.id_house
        JOIN fact_house_listing_flows f
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
        SELECT
            f.sk_house_listing,
            f.status_history,
            d.date,
            d.week_start,
            d.weekday_name,
            d.month_start,
            d.month_end,
            ROW_NUMBER() OVER(PARTITION BY f.sk_house_listing, d.date ORDER BY f.ts_status_start DESC) AS order_status -- daily order status
        FROM
            fact_house_listing_status f
        JOIN dim_date d 
            ON d.sk_date between nullif(f.sk_status_start_date,-1) AND COALESCE(to_char(to_date(nullif(sk_status_end_date, -1), 'YYYYMMDD') - 1, 'YYYYMMDD')::bigint, to_char(current_date -1, 'YYYYMMDD')::bigint)
        WHERE
            f.status_history = 'publicado' -- consider only published status
            AND substring(sk_house_listing,10,12) <> '000' -- consider only listings that already started publication
            AND date >= '2021-02-01' -- Month when the campaign started
    
    )
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
    LEFT JOIN fact_house_listings fhl 
        ON fhs.sk_house_listing = fhl.sk_house_listing
    LEFT JOIN houses_w_plaquinhas hp
        ON fhl.sk_house_listing/1000 = hp.id_house
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
        JOIN sale.fact_listing_flows flf
            ON flf.sk_house_listing/1000 = hp.id_house
        WHERE 
            flf.sk_condo > 0
        GROUP BY 
            1,2,3,4
    ),
    daily_published_listings_sale AS (
    ----------------------------
    -- Ongoing listings query --
    ----------------------------
        SELECT
            f.sk_sale_listing AS sk_house_listing,
            f.status_history,
            d.date,
            d.week_start,
            d.weekday_name,
            d.month_start,
            d.month_end,
            ROW_NUMBER() OVER(PARTITION BY f.sk_sale_listing, d.date ORDER BY f.ts_status_started DESC) AS order_status -- daily order status
        FROM
            sale.fact_listing_status f
        JOIN dim_date d 
            ON d.sk_date between nullif(f.sk_status_start_date,-1) AND COALESCE(to_char(to_date(nullif(sk_status_end_date, -1), 'YYYYMMDD') - 1, 'YYYYMMDD')::bigint, to_char(current_date -1, 'YYYYMMDD')::bigint)
        WHERE
            f.status_history = 'PUBLISHED' -- consider only published status
            AND date >= '2021-09-01' -- Month when the campaign started
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
    LEFT JOIN sale.fact_listing_flows flf 
        ON fhs.sk_house_listing/1000 = flf.sk_house_listing/1000
    LEFT JOIN houses_w_plaquinhas hp
        ON fhs.sk_house_listing/1000 = hp.id_house
    LEFT JOIN condo_w_plaquinhas_sale cps
        ON flf.sk_condo = cps.sk_condo
    WHERE
        fhs.order_status = 1
        AND flf.sk_region > 0
),
metrics_base AS (
    SELECT
        pr.sk_house_listing/1000 AS id_house,
        'Rent' AS business_context,
        dr.short_region_name,
        dr.city_group,
        dr.city_name,
        dr.name AS subregion_name,
        pr.installation_type,
        pr.listing_type,
        pr.weekday_name,
        CASE
            WHEN pr.id_plaquinha IS NOT NULL 
                AND pr.dt_plaquinha <= pr.date THEN TRUE
            ELSE FALSE
        END AS has_plaquinha, -- flag to identify if the house or the house condo has plaquinha
        CASE
            WHEN pr.id_plaquinha_house IS NOT NULL 
                AND pr.dt_plaquinha_house <= pr.date THEN TRUE
            ELSE FALSE
        END AS has_plaquinha_house, -- flag to identify if the house has plaquinha
        pr.month_end AS dt_month_end,
        pr.date AS dt,
        pr.dt_plaquinha AS dt_plaquinha_installed,
        pr.dt_plaquinha_house AS dt_plaquinha_installed_house,
        NULL::FLOAT AS new_installed_plaquinhas_target,
        NULL::FLOAT AS active_plaquinhas_target,
        NULL::FLOAT AS cover_percent_target
    FROM
        plaquinhas_rent pr
    LEFT JOIN public.dim_region dr
        ON pr.sk_region = dr.sk_region
    GROUP BY 
        1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18
    UNION
    SELECT
        ps.sk_house_listing/1000 AS id_house,
        'Sale' AS business_context,
        dr.short_region_name,
        dr.city_group,
        dr.city_name,
        dr.name AS subregion_name,
        ps.installation_type,
        ps.listing_type,
        ps.weekday_name,
        CASE
            WHEN ps.id_plaquinha IS NOT NULL 
                AND ps.dt_plaquinha <= ps.date THEN TRUE
            ELSE FALSE
        END AS has_plaquinha, -- flag to identify if the house or the house condo has plaquinha
        CASE
            WHEN ps.id_plaquinha_house IS NOT NULL 
                AND ps.dt_plaquinha_house <= ps.date THEN TRUE
            ELSE FALSE
        END AS has_plaquinha_house, -- flag to identify if the house has plaquinha
        ps.month_end AS dt_month_end,
        ps.date AS dt,
        ps.dt_plaquinha AS dt_plaquinha_installed,
        ps.dt_plaquinha_house AS dt_plaquinha_installed_house,
        NULL::FLOAT AS new_installed_plaquinhas_target,
        NULL::FLOAT AS active_plaquinhas_target,
        NULL::FLOAT AS cover_percent_target
    FROM
        plaquinhas_sale ps
    LEFT JOIN public.dim_region dr
        ON ps.sk_region = dr.sk_region
    GROUP BY 
        1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18
),
targets AS (
    -------------------------------------
    -- New installed plaquinhas target --
    -------------------------------------
    SELECT 
        NULL::INT AS id_house,
        tgt.business_context,
        NULL::TEXT AS short_region_name,
        city_group AS city_group,
        NULL::TEXT AS city_name,
        NULL::TEXT AS subregion_name,
        NULL::TEXT AS installation_type,
        listing_type AS listing_type,
        NULL::TEXT AS weekday_name,
        NULL::BOOL AS has_plaquinha,
        NULL::BOOL AS has_plaquinha_house,
        NULL::DATE AS dt_month_end,
        NULL::DATE AS dt,
        NULL::DATE AS dt_plaquinha_installed,
        tgt.dt_target AS dt_plaquinha_installed_house,
        tgt.new_installed_plaquinhas_target,
        NULL::FLOAT AS active_plaquinhas_target,
        NULL::FLOAT AS cover_percent_target
    FROM 
        datalake_gsheets_clean_prod.plaquinhas_installation_targets tgt
    UNION ALL 
    ------------------------------
    -- Active plaquinhas target --
    ------------------------------
    SELECT 
        NULL::INT AS id_house,
        tgt.business_context,
        NULL::TEXT AS short_region_name,
        city_group AS city_group,
        NULL::TEXT AS city_name,
        NULL::TEXT AS subregion_name,
        NULL::TEXT AS installation_type,
        listing_type AS listing_type,
        NULL::TEXT AS weekday_name,
        NULL::BOOL AS has_plaquinha,
        NULL::BOOL AS has_plaquinha_house,
        NULL::DATE AS dt_month_end,
        tgt.dt_target AS dt,
        NULL::DATE AS dt_plaquinha_installed,
        NULL::DATE AS dt_plaquinha_installed_house,
        NULL::FLOAT AS new_installed_plaquinhas_target,
        tgt.active_plaquinhas_target,
        tgt.cover_percent_target
    FROM 
        datalake_gsheets_clean_prod.plaquinhas_installation_targets tgt
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