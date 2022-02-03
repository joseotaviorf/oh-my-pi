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
            h.type AS type,
            FALSE AS is_platform_property,
            h.ts_updated
        FROM 
            sale.dim_listing AS l 
        LEFT JOIN 
            quintoandar.dim_house AS h
                ON h.sk_house = l.sk_house 
        WHERE 
            l.status IN ('PUBLISHED', 'UNPUBLISHED')
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
            q.ts_updated,
            q.type
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
            h.type, 
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
            type IN ('Apartamento', 'StudioOuKitchenette') 
            AND TRUNC(week_start) >= TO_DATE('2021-08-1', 'YYYY-MM-DD')
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
            type IN ('Apartamento', 'StudioOuKitchenette') 
            AND TRUNC(week_start) >= TO_DATE('2021-08-1', 'YYYY-MM-DD')
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
        (CAST((me.ongoing_listings - LAG(me.ongoing_listings, 1) OVER (PARTITION by r.sk_region ORDER BY me.week_start)) AS FLOAT)/NULLIF(me.ongoing_listings, 0)) * 100 AS ol_variation,
        me.property_listings,
        me.exclusive_listings AS uniqueness_listings,
        (CAST((me.exclusive_listings - LAG(me.exclusive_listings, 1) OVER (PARTITION by r.sk_region ORDER BY me.week_start)) AS FLOAT)/NULLIF(me.exclusive_listings, 0)) * 100 AS uniqueness_variation,
        CAST(me.exclusive_listings AS FLOAT)/NULLIF(me.ongoing_listings, 0) AS proportion_uniqueness_listings,
        COALESCE(fl.first_listings, 0) AS first_listings,
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
            d.week_start,
            f.id_house,
            f.status_history,
            f.weeks_published, 
            ROW_NUMBER() OVER (PARTITION BY id_house, status_history, week_start ORDER BY ts_started_date) AS order_status
        FROM 
            datamarts.loft_status_listing_flows AS f
        JOIN 
            dim_date AS d
                ON d.sk_date BETWEEN NULLIF(CAST(TO_CHAR(DATE(ts_started_date),'YYYYMMDD') AS BIGINT),-1) 
                AND coalesce(NULLIF(CAST(TO_CHAR(DATE(ts_ended_date),'YYYYMMDD') AS BIGINT), -1), CAST(TO_CHAR(date(ts_load),'YYYYMMDD') AS BIGINT))
        WHERE 
            d.date = d.week_start
    ),
    metrics AS (
        SELECT 
            b.week_start,
            l.id_neighborhood, 
            l.neighborhood,
            l.city, 
            COUNT(
                DISTINCT 
                    CASE 
                        WHEN status_history = 'Publicado' THEN b.id_house 
                        ELSE NULL 
                    END) AS ongoing_listings,
            COUNT(
                DISTINCT 
                    CASE 
                        WHEN status_history = 'Despublicado' THEN b.id_house 
                        ELSE 
                    NULL END) AS base_unpublished_listings,
            COUNT(
                DISTINCT 
                    CASE 
                        WHEN is_platform_property = 'True' AND status_history = 'Publicado' THEN b.id_house 
                        ELSE NULL 
                    END) AS property_listings,
            COUNT(
                DISTINCT 
                    CASE 
                        WHEN is_exclusive = 'True' AND status_history = 'Publicado' THEN b.id_house 
                        ELSE NULL 
                    END) AS exclusive_listings,
            AVG(price_m2) AS mean_price_m2
        FROM
            base AS b 
        LEFT JOIN 
            datamarts.loft_house_listing AS l
                ON b.id_house = l.id_house
        WHERE 
            b.order_status = 1
        GROUP BY 
            1, 2, 3, 4 
    ),
    median_price AS (
        SELECT
            week_start,
            id_neighborhood,
            neighborhood,
            MEDIAN(price_m2::FLOAT) AS median_price_m2
        FROM
            base AS b 
        LEFT JOIN 
            datamarts.loft_house_listing AS l
                ON b.id_house = l.id_house
        WHERE 
            b.order_status = 1
        GROUP BY 
            1, 2, 3
    ),
    first_listings AS (
        WITH base AS (
            SELECT 
                id_neighborhood,
                neighborhood,
                status_history,
                ROW_NUMBER() OVER (PARTITION BY id_house, status_history ORDER BY ts_ended_date DESC) AS order_status,
                ts_started_date
            FROM datamarts.loft_status_listing_flows
        )
        SELECT 
            d.week_start,
            id_neighborhood,
            neighborhood,
            COUNT(*) AS first_listings,
            COUNT(*) AS publications
        FROM 
            base
        JOIN 
            dim_date AS d
                ON d.sk_date = CAST(TO_CHAR(DATE(ts_started_date),'YYYYMMDD') AS BIGINT)
        WHERE 
            order_status = 1 
            AND status_history = 'Publicado'
        GROUP BY 
            1, 2, 3
    ),
    despublications AS (
        SELECT 
            d.week_start,
            id_neighborhood,
            neighborhood,
            COUNT(*) AS depublication
        FROM 
            datamarts.loft_status_listing_flows
        JOIN 
            dim_date AS d
                ON d.sk_date = CAST(TO_CHAR(date(ts_started_date),'YYYYMMDD') AS BIGINT)
        WHERE 
            status_history = 'Despublicado'
            AND d.date = d.week_start
        GROUP BY 
            1, 2, 3
    )
    SELECT 
        me.week_start::DATE,
        'Loft' AS platform,
        me.id_neighborhood::BIGINT AS sk_region,
        COALESCE(r.city_name::VARCHAR, me.city) AS city, 
        me.neighborhood::VARCHAR,
        me.ongoing_listings::BIGINT,
        (CAST((me.ongoing_listings - LAG(me.ongoing_listings, 1) OVER (PARTITION by r.sk_region, me.neighborhood ORDER BY me.week_start)) AS FLOAT)/NULLIF(me.ongoing_listings, 0)) * 100 AS ol_variation,
        me.property_listings::BIGINT,
        me.exclusive_listings::BIGINT AS uniqueness_listings,
        (CAST((me.exclusive_listings - LAG(me.exclusive_listings, 1) OVER (PARTITION by r.sk_region, me.neighborhood ORDER BY me.week_start)) AS FLOAT)/NULLIF(me.exclusive_listings, 0)) * 100 AS uniqueness_variation,
        CAST(me.exclusive_listings AS FLOAT)/NULLIF(me.ongoing_listings, 0) AS proportion_uniqueness_listings,
        COALESCE(fl.first_listings, 0) AS first_listings,
        COALESCE(LAG(dp.depublication, 1) OVER (ORDER BY me.week_start), 0) AS depublication,
        CAST(COALESCE(dp.depublication, 0) AS FLOAT)/NULLIF(me.ongoing_listings, 0) AS unpl_by_ol,
        CAST(COALESCE(fl.publications, 0) - COALESCE(LAG(dp.depublication, 1) OVER (ORDER BY me.week_start), 0) AS FLOAT)/NULLIF(me.ongoing_listings, 0) AS pl_variation,
        mean_price_m2::FLOAT,
        median_price_m2::FLOAT
    FROM 
        metrics AS me 
    LEFT JOIN 
        dim_region AS r 
            ON  me.id_neighborhood = r.id
            AND me.neighborhood = r.name
    LEFT JOIN 
        first_listings AS fl 
            ON me.week_start = fl.week_start
            AND me.id_neighborhood = fl.id_neighborhood
            AND me.neighborhood = fl.neighborhood
    LEFT JOIN 
        despublications AS dp 
            ON me.week_start = dp.week_start
            AND me.id_neighborhood = dp.id_neighborhood
            AND me.neighborhood = dp.neighborhood
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
    first_listings,
    depublication,
    unpl_by_ol,
    pl_variation,
    mean_price_m2,
    median_price_m2 
FROM 
    union_clean


