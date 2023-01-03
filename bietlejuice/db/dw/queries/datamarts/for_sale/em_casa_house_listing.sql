WITH em_casa_listings_raw AS (
    SELECT
        CONCAT(id, 'Emcasa', CAST(ROW_NUMBER() OVER (PARTITION BY id ORDER BY CAST(CONCAT(CAST(year AS VARCHAR), '-', CAST(month AS VARCHAR), '-', CAST(day AS VARCHAR)) AS DATE)) AS VARCHAR)) AS sk_house,
        id AS id_house_platform,
        CONCAT(id, 'Emcasa') AS id_house,
        'Emcasa' AS platform,
        CAST(address.neighborhood AS VARCHAR) AS neighborhood,
        CAST(address.city AS VARCHAR) AS city,
        CAST(address.state AS VARCHAR) AS state,
        CAST(address.street AS VARCHAR) AS address,
        REGEXP_REPLACE(LOWER(CAST(address.street AS VARCHAR)), 'avenida|rua|av.|#|&|1|2|3|4|5|6|7|8|9| da | de | do | das | dos ') AS address_for_join,
        NULL AS st_number,
        NULL AS zip_code,
        CAST(geolocation.latitude AS VARCHAR) AS lat,
        CAST(geolocation.longitude AS VARCHAR) AS lng,
        CAST(house_info.floor AS VARCHAR) AS floors,
        CAST(house_info.num_floors AS VARCHAR) AS num_floors,
        CAST(house_info.unit_per_floor AS INTEGER) AS unit_per_floor,
        CAST(house_info.area AS INTEGER) AS total_area,
        CAST(house_info.bedrooms AS INTEGER) AS bedrooms,
        CAST(house_info.suites AS INTEGER) AS suites,
        CAST(house_info.parking_spaces AS INTEGER) AS parking_spaces,
        CAST(house_info.bathrooms AS INTEGER) AS bathrooms,
        NULL AS year_built,
        CONCAT(UPPER(SUBSTR(CAST(house_info.unit_type AS VARCHAR), 1, 1)), LOWER(SUBSTR(CAST(house_info.unit_type AS VARCHAR), 2, 15))) AS unit_type,
        NULL AS usage_type,
        CAST(price.sale.price AS DOUBLE) AS price,
        (CAST(price.sale.price AS DOUBLE)/CAST(house_info.area AS INTEGER)) AS price_m2,
        CAST(price.sale.condo_fee AS DOUBLE) AS condo_fee,
        CAST(price.sale.iptu AS DOUBLE) AS iptu,
        CAST(type.buyable AS BOOLEAN) AS for_sale,
        CAST(type.rentable AS BOOLEAN) AS for_rent,
        'False' AS is_platform_property,
        CASE
            WHEN ROW_NUMBER() OVER (PARTITION BY id ORDER BY CAST(CONCAT(CAST(year AS VARCHAR), '-', CAST(month AS VARCHAR), '-', CAST(day AS VARCHAR)) AS DATE) DESC) = 1 THEN 1
        END AS is_last_status,
        CAST(CONCAT(CAST(year AS VARCHAR), '-', CAST(month AS VARCHAR), '-', CAST(day AS VARCHAR)) AS DATE) AS ts_updated,
        FIRST_VALUE(CAST(CONCAT(CAST(year AS VARCHAR), '-', CAST(month AS VARCHAR), '-', CAST(day AS VARCHAR)) AS DATE)) OVER (PARTITION BY id ORDER BY CAST(CONCAT(CAST(year AS VARCHAR), '-', CAST(month AS VARCHAR), '-', CAST(day AS VARCHAR)) AS DATE) DESC) AS ts_last_publication,
        FIRST_VALUE(CAST(CONCAT(CAST(year AS VARCHAR), '-', CAST(month AS VARCHAR), '-', CAST(day AS VARCHAR)) AS DATE)) OVER (PARTITION BY 1 ORDER BY CAST(CONCAT(CAST(year AS VARCHAR), '-', CAST(month AS VARCHAR), '-', CAST(day AS VARCHAR)) AS DATE) DESC) AS ts_last_extraction
    FROM
        datalake_crawlers_listings_clean_prod.em_casa
),
qa_listings AS (
    WITH house_latlong_raw AS (
        SELECT
            id,
            CAST(lat AS VARCHAR) AS lat,
            CAST(lng AS VARCHAR) AS lng
        FROM
            datalake_ebdb_clean_prod.house
    ), 
    only_qa AS (
        SELECT
            CAST(h.id AS VARCHAR) AS id,
            rh.lat,
            rh.lng,
            REGEXP_REPLACE(LOWER(address), 'avenida|rua|av.|#|&|1|2|3|4|5|6|7|8|9| da | de | do | das | dos ') AS address_for_join,
            (CAST(h.sale_price AS INTEGER)/CAST(h.total_area AS DOUBLE)) AS price_m2
        FROM
            datalake_ebdb_clean_prod.house AS h
        LEFT JOIN
            datalake_ebdb_clean_prod.listing_business_context AS bc
                ON h.id = bc.id_house
        LEFT JOIN
            house_latlong_raw AS rh
                ON h.id = rh.id
        WHERE
            bc.business_context = 'SALE'
            AND bc.status = 'PUBLISHED'
            AND h.type IN ('Apartamento', 'StudioOuKitchenette')   
    ),
    only_cm AS (
        SELECT
            h.id,
            CAST(lat AS VARCHAR) AS lat,
            CAST(lng AS VARCHAR) AS lng,
            REGEXP_REPLACE(LOWER(address), 'avenida|rua|av.|#|&|1|2|3|4|5|6|7|8|9| da | de | do | das | dos ') AS address_for_join,
            (CAST(price AS INTEGER)/CAST(total_area AS DOUBLE)) AS price_m2
        FROM
            datalake_casa_mineira_crm_clean_prod.house AS h
        LEFT JOIN
            datalake_casa_mineira_crm_clean_prod.house_type AS t 
                ON t.id = h.id_type
        LEFT JOIN
            datalake_casa_mineira_crm_clean_prod.house_status AS s
                ON s.id = h.id_status
        WHERE
            id_status = '3'
            AND id_house_quintoandar IS NULL
            AND t.house_type_name in ('Apartamento', 'Cobertura', 'Flat')
    )
    SELECT 
        *
    FROM 
        only_qa 
    -----------------
    UNION 
    -----------------
    SELECT 
        *
    FROM 
        only_cm
),
dataset_distances AS (
    WITH em_casa_listings_w_latlong AS (
        SELECT DISTINCT
            id_house_platform,
            lat,
            lng,
            address_for_join
        FROM
            em_casa_listings_raw
        WHERE
            is_last_status = 1
    ),
    distance_em_casa_to_5a AS (
        SELECT
            ec.id_house_platform,
            q.price_m2,
            (6371 * ACOS(COS(RADIANS(CAST(q.lat AS DOUBLE))) * COS(RADIANS(CAST(ec.lat AS DOUBLE))) * COS(RADIANS(CAST(q.lng AS DOUBLE)) - RADIANS(CAST(ec.lng AS DOUBLE))) + SIN(RADIANS(CAST(q.lat AS DOUBLE))) * SIN(RADIANS(CAST(ec.lat AS DOUBLE))))) AS distance
        FROM
            em_casa_listings_w_latlong AS ec
        JOIN
            qa_listings AS q
                ON (6371 * ACOS(COS(RADIANS(CAST(q.lat AS DOUBLE))) * COS(RADIANS(CAST(ec.lat AS DOUBLE))) * COS(RADIANS(CAST(q.lng AS DOUBLE)) - RADIANS(CAST(ec.lng AS DOUBLE))) + SIN(RADIANS(CAST(q.lat AS DOUBLE))) * SIN(RADIANS(CAST(ec.lat AS DOUBLE))))) <= 0.05
                AND LEVENSHTEIN_DISTANCE(q.address_for_join, ec.address_for_join) <= 4
                OR (6371 * ACOS(COS(RADIANS(CAST(q.lat AS DOUBLE))) * COS(RADIANS(CAST(ec.lat AS DOUBLE))) * COS(RADIANS(CAST(q.lng AS DOUBLE)) - RADIANS(CAST(ec.lng AS DOUBLE))) + SIN(RADIANS(CAST(q.lat AS DOUBLE))) * SIN(RADIANS(CAST(ec.lat AS DOUBLE))))) <= 0.01
    )
    SELECT
        id_house_platform AS id_house_platform,
        COUNT(id_house_platform) AS nearby_other_platform_houses,
        AVG(price_m2) AS avg_nearby_price_m2,
        AVG(distance) AS avg_distance
    FROM
        distance_em_casa_to_5a
    GROUP BY
        1
),
regions AS (
    SELECT
        r.id AS id_neighborhood,
        r.name AS neighborhood,
        r.city_name AS city,
        ST_POLYGON(pr.polygon) AS geometry
    FROM
        datalake_ebdb_clean_prod.polygon_region AS pr
    JOIN
        datalake_ebdb_clean_prod.map_region AS r
            ON r.id = pr.id_region
    WHERE
        r.level = 'SubRegiao'
),
regions_for_city_group AS (
    SELECT
        city_name AS city_for_em_casa,
        city_group AS city_group_for_em_casa
    FROM
        datalake_clean.ods_dim_region
    WHERE
        level = 'SubRegiao'
    GROUP BY 
        1, 2
    HAVING
        city_group != ''
),
em_casa_listings_w_correct_regions AS (
    SELECT
        ec.sk_house,
        ec.id_house,
        ec.id_house_platform,
        IF(r.id_neighborhood IS NULL, CAST(-1 AS BIGINT), r.id_neighborhood) AS id_neighborhood,
        ec.platform,
        IF(r.city IS NULL, ec.city, r.city) AS city,
        rcg.city_group_for_em_casa AS city_group,
        IF(r.neighborhood IS NULL, ec.neighborhood, r.neighborhood) AS neighborhood,
        ec.neighborhood AS neighborhood_em_casa,
        ec.state,
        ec.lat,
        ec.lng,
        ec.address,
        ec.zip_code,
        ec.st_number,
        ec.floors,
        ec.num_floors,
        ec.unit_per_floor,
        ec.total_area,
        ec.bedrooms,
        ec.suites,
        ec.parking_spaces,
        ec.bathrooms,
        ec.year_built,
        ec.unit_type,
        ec.usage_type,
        ec.price,
        ec.price_m2,
        ec.condo_fee,
        ec.iptu,
        ec.for_sale,
        ec.for_rent,
        dd.nearby_other_platform_houses,
        dd.avg_nearby_price_m2,
        dd.avg_distance,
        ec.is_platform_property,
        ec.is_last_status,
        CASE
            WHEN ec.is_platform_property = 'True' THEN 'True'
            WHEN r.id_neighborhood IS NULL
                AND dd.nearby_other_platform_houses <= 1 THEN 'True'
            WHEN dd.nearby_other_platform_houses IS NULL THEN 'True'
            ELSE 'False'
        END AS is_exclusive,
        ec.ts_updated,
        ec.ts_last_extraction,
        ec.ts_last_publication
    FROM
        em_casa_listings_raw AS ec
    LEFT JOIN
        regions AS r
            ON ST_WITHIN(ST_POINT(CAST(ec.lng AS DOUBLE), CAST(ec.lat AS DOUBLE)), r.geometry)
    LEFT JOIN
        dataset_distances AS dd
            ON ec.id_house_platform = dd.id_house_platform
    LEFT JOIN
        regions_for_city_group AS rcg
            ON ec.city = rcg.city_for_em_casa
    WHERE
        ec.is_last_status = 1
),
full_dataset AS (
    WITH ids_duplicados AS (
        SELECT
            id_house
        FROM
            em_casa_listings_w_correct_regions
        GROUP BY 1
        HAVING
            COUNT(*) = 2
    ),
    correct_duplicated_values AS (
        SELECT
            sk_house,
            id_house,
            id_house_platform,
            id_neighborhood,
            platform,
            city,
            city_group,
            neighborhood,
            neighborhood_em_casa,
            state,
            lat,
            lng,
            address,
            zip_code,
            st_number,
            floors,
            num_floors,
            unit_per_floor,
            total_area,
            bedrooms,
            suites,
            parking_spaces,
            bathrooms,
            year_built,
            unit_type,
            usage_type,
            price,
            price_m2,
            condo_fee,
            iptu,
            for_sale,
            for_rent,
            nearby_other_platform_houses,
            avg_nearby_price_m2,
            avg_distance,
            is_platform_property,
            is_last_status,
            is_exclusive,
            ts_updated,
            ts_last_publication,
            ts_last_extraction
        FROM
            em_casa_listings_w_correct_regions
        WHERE
            id_house IN (SELECT id_house FROM ids_duplicados)
            AND neighborhood = neighborhood_em_casa
    )
    SELECT
        sk_house,
        id_house,
        id_house_platform,
        id_neighborhood,
        platform,
        city,
        city_group,
        neighborhood,
        neighborhood_em_casa,
        state,
        lat,
        lng,
        address,
        st_number,
        zip_code,
        floors,
        num_floors,
        unit_per_floor,
        total_area,
        bedrooms,
        suites,
        parking_spaces,
        bathrooms,
        year_built,
        unit_type,
        usage_type,
        price,
        price_m2,
        condo_fee,
        iptu,
        for_sale,
        for_rent,
        nearby_other_platform_houses,
        avg_nearby_price_m2,
        avg_distance,
        is_platform_property,
        is_last_status,
        is_exclusive,
        ts_updated,
        ts_last_publication,
        ts_last_extraction
    FROM
        em_casa_listings_w_correct_regions
    WHERE
        id_house NOT IN (SELECT id_house FROM ids_duplicados)
    --------------
    UNION
    --------------
    SELECT
        sk_house,
        id_house,
        id_house_platform,
        id_neighborhood,
        platform,
        city,
        city_group,
        neighborhood,
        neighborhood_em_casa,
        state,
        lat,
        lng,
        address,
        st_number,
        zip_code,
        floors,
        num_floors,
        unit_per_floor,
        total_area,
        bedrooms,
        suites,
        parking_spaces,
        bathrooms,
        year_built,
        unit_type,
        usage_type,
        price,
        price_m2,
        condo_fee,
        iptu,
        for_sale,
        for_rent,
        nearby_other_platform_houses,
        avg_nearby_price_m2,
        avg_distance,
        is_platform_property,
        is_last_status,
        is_exclusive,
        ts_updated,
        ts_last_publication,
        ts_last_extraction
    FROM
        correct_duplicated_values

),
listings_clean AS (
    SELECT
        sk_house,
        id_house,
        id_house_platform,
        id_neighborhood,
        platform,
        CASE
            WHEN is_last_status = 1
                AND ts_last_publication = ts_last_extraction THEN 'Publicado'
            WHEN is_last_status IS NULL THEN 'Publicado'
            ELSE 'Despublicado'
        END AS status,
        city,
        city_group,
        neighborhood,
        state,
        lat,
        lng,
        address,
        st_number,
        zip_code,
        floors,
        num_floors,
        unit_per_floor,
        total_area,
        bedrooms,
        suites,
        parking_spaces,
        bathrooms,
        year_built,
        unit_type,
        usage_type,
        price,
        price_m2,
        condo_fee,
        iptu,
        for_sale,
        for_rent,
        nearby_other_platform_houses,
        avg_nearby_price_m2,
        avg_distance,
        is_platform_property,
        is_exclusive,
        ts_updated
    FROM
        full_dataset
)
SELECT
    sk_house,
    id_house,
    id_house_platform,
    id_neighborhood,
    platform,
    status,
    city,
    city_group,
    neighborhood,
    state,
    lat,
    lng,
    address,
    st_number,
    zip_code,
    floors,
    num_floors,
    unit_per_floor,
    total_area,
    bedrooms,
    suites,
    parking_spaces,
    bathrooms,
    year_built,
    unit_type,
    usage_type,
    price,
    price_m2,
    condo_fee,
    iptu,
    for_sale,
    for_rent,
    nearby_other_platform_houses,
    avg_nearby_price_m2,
    avg_distance,
    is_platform_property,
    is_exclusive,
    ts_updated,
    NOW() AS ts_load
FROM
    listings_clean 