WITH qa_part AS (
    WITH qa_listings_raw AS (
        SELECT 
            h.sk_house AS id_house,
            h.sk_house AS id_house_platform,
            'Quintoandar' AS platform, 
            h.total_area,
            CAST(h.lat AS VARCHAR) AS lat,
            CAST(h.lng AS VARCHAR) AS lng,
            l.price AS price,
            l.price/NULLIF(h.total_area::FLOAT, 0) AS price_m2,
            FALSE AS is_platform_property,
            h.ts_updated
        FROM 
            sale.dim_listing AS l 
        LEFT JOIN 
            quintoandar.dim_house AS h
                ON h.sk_house = l.sk_house 
        WHERE 
            l.status IN ('PUBLISHED', 'UNPUBLISHED')
            AND h.type IN ('Apartamento', 'StudioOuKitchenette') 
    ),
    loft_listings_to_distance AS ( 
        SELECT 
            id_house,
            lat,
            lng,
            price_m2
        FROM 
            datamarts.loft_house_listing
        WHERE 
            status = 'Publicado' 
    ),
    distance_loft_to_5a AS (
        SELECT
            q.id_house,
            l.price_m2,
            (6371 * ACOS(COS(RADIANS(CAST(q.lat AS FLOAT))) * COS(RADIANS(CAST(l.lat AS FLOAT))) * COS(RADIANS(CAST(q.lng AS FLOAT)) - RADIANS(CAST(l.lng AS FLOAT))) + SIN(RADIANS(CAST(q.lat AS FLOAT))) * SIN(RADIANS(CAST(l.lat AS FLOAT))))) AS distance
        FROM
            qa_listings_raw AS q
        JOIN
            loft_listings_to_distance AS l
                ON (6371 * ACOS(COS(RADIANS(CAST(q.lat AS FLOAT))) * COS(RADIANS(CAST(l.lat AS FLOAT))) * COS(RADIANS(CAST(q.lng AS FLOAT)) - RADIANS(CAST(l.lng AS FLOAT))) + SIN(RADIANS(CAST(q.lat AS FLOAT))) * SIN(RADIANS(CAST(l.lat AS FLOAT))))) <= 0.05
    ),
    dataset_distances AS (
        SELECT
            id_house AS id_house,
            COUNT(id_house) AS nearby_other_platform_houses,
            AVG(price_m2) AS avg_nearby_price_m2,
            AVG(distance) AS avg_distance
        FROM
            distance_loft_to_5a
        GROUP BY 
            1
    ),
    qa_listings AS (
        SELECT
            q.id_house,
            q.price,
            q.price_m2,
            q.is_platform_property,
            CASE
                WHEN dd.nearby_other_platform_houses IS NULL THEN TRUE
                ELSE FALSE
            END AS is_exclusive,
            dd.nearby_other_platform_houses,
            dd.avg_nearby_price_m2,
            dd.avg_distance,
            q.ts_updated
        FROM
            qa_listings_raw AS q
        LEFT JOIN
            dataset_distances AS dd
                ON q.id_house = dd.id_house
    ),
    ol AS (
        SELECT
            f.sk_sale_listing,
            f.status_history,
            f.sk_status_start_date,
            f.sk_status_end_date,
            f.sk_region,
            d.date,
            d.week_start,
            d.weekday_name,
            h.price_m2,
            ROW_NUMBER() OVER(PARTITION BY f.sk_sale_listing, d.date ORDER BY f.ts_status_started DESC) AS order_status,
            h.is_platform_property,
            h.is_exclusive
        FROM 
            sale.fact_listing_status AS f
        JOIN 
            dim_date AS d
                ON d.sk_date BETWEEN NULLIF(CAST(TO_CHAR(DATE(f.ts_status_started),'YYYYMMDD') AS BIGINT),-1) 
                AND coalesce(NULLIF(CAST(TO_CHAR(DATE(f.ts_status_ended),'YYYYMMDD') AS BIGINT), -1), CAST(REPLACE(CAST(CURRENT_DATE AS VARCHAR), '-', '') AS BIGINT) - 1)
        LEFT JOIN 
            qa_listings AS h 
                ON (f.sk_sale_listing/1000) = h.id_house
        WHERE 
            f.status_history IN ('PUBLISHED', 'UNPUBLISHED')
            AND d.date = d.week_start
    ),
    metrics AS ( 
        SELECT
            week_start,
            sk_region,
            COUNT
                (DISTINCT 
                    CASE 
                        WHEN status_history = 'PUBLISHED' THEN sk_sale_listing 
                        ELSE NULL 
                    END) AS ongoing_listings,
            COUNT(
                DISTINCT 
                    CASE 
                        WHEN status_history = 'UNPUBLISHED' THEN sk_sale_listing 
                        ELSE NULL 
                    END) AS base_depublished_listings,
            COUNT(
                DISTINCT 
                    CASE 
                        WHEN is_platform_property IS TRUE AND status_history = 'PUBLISHED' THEN sk_sale_listing 
                        ELSE NULL 
                    END) AS property_listings,
            COUNT(
                DISTINCT 
                    CASE 
                        WHEN is_exclusive = TRUE AND status_history = 'PUBLISHED' THEN sk_sale_listing 
                        ELSE NULL 
                    END) AS exclusive_listings,
            AVG(
                DISTINCT 
                    CASE 
                        WHEN status_history = 'PUBLISHED' THEN price_m2 
                        ELSE NULL 
                    END) AS mean_price_m2
        FROM  
            ol
        WHERE 
            TRUNC(week_start) >= TO_DATE('2021-08-1', 'YYYY-MM-DD')
        GROUP BY 
            1, 2
    ),
    median_price AS (
        SELECT
            week_start,
            sk_region, 
            MEDIAN(price_m2) AS median_price_m2
        FROM  
            ol
        WHERE 
            TRUNC(week_start) >= TO_DATE('2021-08-1', 'YYYY-MM-DD')
        GROUP BY 
            1, 2
    ),
    fl AS (
        SELECT 
            d.week_start,
            f.sk_region,
            COUNT(*) AS first_listings
        FROM
            sale.dim_listing AS l
        LEFT JOIN 
            quintoandar.dim_house AS h 
                ON h.sk_house = l.sk_house
        LEFT JOIN 
            sale.fact_listings AS f
            ON h.sk_house = f.sk_house
        JOIN 
            dim_date AS d 
                ON f.sk_first_publication_date = d.sk_date
        WHERE 
            f.sk_first_publication_date != -1 
            AND f.sk_first_publication_date >= 20210801
        GROUP BY 
            1, 2
    ),
    pub AS (
        SELECT 
            d.week_start,
            f.sk_region,
            COUNT(*) AS publications
        FROM
            sale.dim_listing AS l
        LEFT JOIN 
            quintoandar.dim_house AS h 
                ON h.sk_house = l.sk_house
        LEFT JOIN 
            sale.fact_listings AS f
                ON h.sk_house = f.sk_house
        JOIN 
            dim_date AS d 
                ON f.sk_last_publication_date = d.sk_date
        WHERE 
            f.sk_last_publication_date != -1 
            AND f.sk_last_publication_date >= 20210801
        GROUP BY 
            1, 2
    ),
    desp AS (
        SELECT 
            d.week_start,
            f.sk_region,
            COUNT(*) AS depublication 
        FROM
            sale.dim_listing AS l
        LEFT JOIN 
            quintoandar.dim_house AS h 
                ON h.sk_house = l.sk_house
        LEFT JOIN 
            sale.fact_listings AS f
                ON h.sk_house = f.sk_house
        JOIN 
            dim_date AS d 
                ON f.sk_last_depublication_date = d.sk_date
        WHERE 
            f.sk_last_depublication_date != -1 
            AND f.sk_last_depublication_date >= 20210801
        GROUP BY 
            1, 2
    )
    SELECT 
        me.week_start,
        'QuintoAndar' AS platform,
        me.sk_region,
        r.city_name AS city,
        r.name AS neighborhood, 
        me.ongoing_listings,
        COALESCE((CAST((me.ongoing_listings - LAG(me.ongoing_listings, 1) OVER (PARTITION by r.sk_region ORDER BY me.week_start)) AS FLOAT)/NULLIF(me.ongoing_listings, 0)) * 100, 0) AS ol_variation,
        me.property_listings,
        me.exclusive_listings AS uniqueness_listings,
        COALESCE((CAST((me.exclusive_listings - LAG(me.exclusive_listings, 1) OVER (PARTITION by r.sk_region ORDER BY me.week_start)) AS FLOAT)/NULLIF(me.exclusive_listings, 0)) * 100, 0) AS uniqueness_variation,
        COALESCE(CAST(me.exclusive_listings AS FLOAT)/NULLIF(me.ongoing_listings, 0), 0) AS proportion_uniqueness_listings,
        COALESCE(pb.publications, 0) AS publications,
        COALESCE(fl.first_listings, 0) AS first_listings,
        (COALESCE(pb.publications, 0) - COALESCE(fl.first_listings, 0)) AS republications,
        COALESCE(dp.depublication, 0) AS depublication,
        COALESCE(dp.depublication, 0)/NULLIF(me.ongoing_listings, 0) AS unpl_by_ol,
        CAST(COALESCE(pb.publications, 0) - COALESCE(dp.depublication, 0) AS FLOAT)/NULLIF(me.ongoing_listings, 0) AS pl_variation,
        me.mean_price_m2,
        md.median_price_m2
    FROM 
        metrics AS me
    LEFT JOIN 
        dim_region AS r 
            ON  me.sk_region = r.sk_region
    LEFT JOIN 
        fl AS fl 
            ON  me.week_start = fl.week_start
            AND me.sk_region = fl.sk_region
    LEFT JOIN 
        pub AS pb 
            ON  me.week_start = pb.week_start
            AND me.sk_region = pb.sk_region
    LEFT JOIN 
        desp AS dp
            ON  me.week_start = dp.week_start
            AND me.sk_region = dp.sk_region
    LEFT JOIN 
        median_price AS md
            ON  me.week_start = md.week_start
            AND me.sk_region = md.sk_region
),
loft_part AS (
    WITH base AS (
        SELECT 
            id_house, 
            id_neighborhood,
            neighborhood,
            status_history,
            is_last_status, 
            ROW_NUMBER() OVER (PARTITION BY id_house ORDER BY ts_started_date) AS order_status,
            ts_started_date,
            ts_ended_date 
        FROM 
            datamarts.loft_status_listing_flows
    ), 
    ongoing_listings AS (
        SELECT 
            d.week_start,
            b.id_house, 
            b.id_neighborhood,
            b.neighborhood, 
            b.status_history, 
            b.is_last_status, 
            b.order_status, 
            b.ts_started_date,
            b.ts_ended_date
        FROM 
            base AS b
        JOIN 
           dim_date AS d
               ON d.sk_date BETWEEN NULLIF(CAST(TO_CHAR(DATE(b.ts_started_date),'YYYYMMDD') AS BIGINT),-1) 
               AND coalesce(NULLIF(CAST(TO_CHAR(DATE(b.ts_ended_date),'YYYYMMDD') AS BIGINT), -1), CAST(TO_CHAR(CURRENT_DATE, 'YYYYMMDD') AS BIGINT) - 1)
        GROUP BY 
            1, 2, 3, 4, 5, 6, 7, 8, 9
    ),
    metrics AS (
        SELECT 
            ol.week_start,
            ol.id_neighborhood, 
            h.city, 
            ol.neighborhood,
            COUNT(
                DISTINCT 
                    CASE 
                        WHEN ol.status_history = 'Publicado' THEN ol.id_house 
                        ELSE NULL 
                    END) AS ongoing_listings,
            COUNT(
                DISTINCT 
                    CASE 
                        WHEN (ol.status_history = 'Publicado' AND  h.is_platform_property = 'True') THEN ol.id_house 
                        ELSE NULL 
                    END) AS property_listings,
            COUNT(
                DISTINCT 
                    CASE 
                        WHEN (ol.status_history = 'Publicado' AND h.is_exclusive = 'True') THEN ol.id_house 
                        ELSE NULL 
                    END) AS uniqueness_listings,
            COUNT(
                DISTINCT 
                    CASE 
                        WHEN (ol.status_history = 'Publicado' AND ol.ts_started_date = week_start) THEN ol.id_house 
                        ELSE NULL 
                    END) AS publications,
            COUNT(
                DISTINCT 
                    CASE 
                        WHEN (ol.status_history = 'Publicado' AND ol.ts_started_date = ol.week_start AND ol.order_status = 1) THEN ol.id_house 
                        ELSE NULL 
                    END) AS first_listings,
            COUNT(
                DISTINCT 
                    CASE 
                        WHEN (ol.status_history = 'Publicado' AND ol.ts_started_date = ol.week_start AND ol.order_status > 2) THEN ol.id_house 
                        ELSE NULL 
                    END) AS republications,
            COUNT(
                DISTINCT 
                    CASE 
                        WHEN (ol.status_history = 'Despublicado' AND ol.ts_started_date = ol.week_start) THEN ol.id_house 
                        ELSE NULL 
                    END) AS depublications,
            AVG(price_m2) AS mean_price_m2
        FROM 
            ongoing_listings AS ol 
        LEFT JOIN 
            datamarts.loft_house_listing AS h
                ON ol.id_house = h.id_house
        GROUP BY 
            1, 2, 3, 4
    ),
    median_price AS (
        SELECT
            ol.week_start,
            ol.id_neighborhood,
            ol.neighborhood,
            MEDIAN(h.price_m2::FLOAT) AS median_price_m2
        FROM
            ongoing_listings AS ol
        LEFT JOIN 
            datamarts.loft_house_listing AS h
                ON ol.id_house = h.id_house
        WHERE 
            ol.order_status = 1
        GROUP BY 
            1, 2, 3
    )
    SELECT 
        me.week_start::DATE,
        'Loft' AS platform,
        me.id_neighborhood::BIGINT AS sk_region,
        COALESCE(r.city_name::VARCHAR, me.city) AS city,
        me.neighborhood::VARCHAR,
        COALESCE(me.ongoing_listings::BIGINT, 0) AS ongoing_listings,
        COALESCE((CAST((me.ongoing_listings - LAG(me.ongoing_listings, 1) OVER (PARTITION by r.sk_region, me.neighborhood ORDER BY me.week_start)) AS FLOAT)/NULLIF(me.ongoing_listings, 0)) * 100, 0) AS ol_variation,
        COALESCE(me.property_listings::BIGINT, 0) AS property_listings,
        COALESCE(me.uniqueness_listings::BIGINT, 0) AS uniqueness_listings,
        COALESCE((CAST((me.uniqueness_listings - LAG(me.uniqueness_listings, 1) OVER (PARTITION by r.sk_region, me.neighborhood ORDER BY me.week_start)) AS FLOAT)/NULLIF(me.uniqueness_listings, 0)) * 100, 0) AS uniqueness_variation,
        me.uniqueness_listings::FLOAT/NULLIF(me.ongoing_listings, 0) AS proportion_uniqueness_listings,
        COALESCE(me.publications, 0) AS publications,
        COALESCE(me.first_listings, 0) AS first_listings,
        COALESCE(me.republications, 0) AS republications, 
        COALESCE(me.depublications, 0) AS depublications,
        COALESCE(me.depublications, 0)::FLOAT/NULLIF(me.ongoing_listings, 0) AS unpl_by_ol,
        COALESCE(me.publications, 0) - COALESCE(LAG(me.depublications, 1) OVER (ORDER BY me.week_start), 0)::FLOAT/NULLIF(me.ongoing_listings, 0) AS pl_variation,
        me.mean_price_m2::FLOAT,
        mp.median_price_m2::FLOAT
    FROM 
        metrics AS me 
    LEFT JOIN 
        dim_region AS r 
            ON  me.id_neighborhood = r.id
            AND me.neighborhood = r.name
    LEFT JOIN 
        median_price AS mp 
            ON me.week_start = mp.week_start
            AND me.id_neighborhood = mp.id_neighborhood
            AND me.neighborhood = mp.neighborhood    
), 
union_clean AS (
    SELECT 
        * 
    FROM 
        loft_part
    -------------------------
    UNION
    -------------------------
    SELECT 
        * 
    FROM 
        qa_part
)
SELECT 
    week_start,
    platform,
    sk_region,
    city,
    neighborhood,
    ongoing_listings,
    ol_variation,
    property_listings,
    uniqueness_listings,
    uniqueness_variation,
    proportion_uniqueness_listings,
    publications,
    first_listings,
    republications, 
    depublications,
    unpl_by_ol,
    pl_variation,
    mean_price_m2,
    median_price_m2 
FROM 
    union_clean