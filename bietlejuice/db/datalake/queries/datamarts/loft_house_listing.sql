WITH loft_listings_raw AS (
    SELECT
        CONCAT(ll.id, 'Loft', CAST(ROW_NUMBER() OVER (PARTITION BY id ORDER BY CAST(CONCAT(CAST(year AS VARCHAR), '-', CAST(month AS VARCHAR), '-', CAST(day AS VARCHAR)) AS DATE)) AS VARCHAR)) AS sk_house,
        ll.id AS id_house_platform,
        CONCAT(ll.id, 'Loft') AS id_house,
        'Loft' AS platform,
        CAST(ll.address.neighborhood AS VARCHAR) AS neighborhood_loft,
        CAST(address.city AS VARCHAR) AS city,
        CAST(ll.address.state AS VARCHAR) AS state,
        CAST(ll.address.street AS VARCHAR) AS address,
        REGEXP_REPLACE(LOWER(CAST(ll.address.street AS VARCHAR)), 'avenida|rua|av.|#|&|1|2|3|4|5|6|7|8|9| da | de | do | das | dos ') AS loft_address_for_join,
        CAST(ll.address.number AS VARCHAR) AS st_number,
        CAST(ll.address.zip_code AS VARCHAR) AS zip_code,
        CAST(ll.geolocation.latitude AS VARCHAR) AS lat,
        CAST(ll.geolocation.longitude AS VARCHAR) AS lng,
        CAST(ll.house_info.floor AS INTEGER) AS floors,
        CAST(ll.house_info.num_floors AS VARCHAR) AS num_floors,
        CAST(ll.house_info.total_area AS INTEGER) AS total_area,
        CAST(ll.house_info.bedrooms AS INTEGER) AS bedrooms,
        CAST(ll.house_info.suites AS INTEGER) AS suites,
        CAST(ll.house_info.parking_spaces AS INTEGER) AS parking_spaces,
        CAST(ll.house_info.bathrooms AS INTEGER) AS bathrooms,
        CAST(ll.house_info.year_built AS INTEGER) AS year_built,
        CONCAT(UPPER(SUBSTR(CAST(ll.house_info.unit_type AS VARCHAR), 1, 1)), LOWER(SUBSTR(CAST(ll.house_info.unit_type AS VARCHAR), 2, 15))) AS unit_type,
        CONCAT(UPPER(SUBSTR(ELEMENT_AT(ll.house_info.usage_type, 1), 1, 1)), LOWER(SUBSTR(ELEMENT_AT(ll.house_info.usage_type, 1), 2, 15))) AS usage_type,
        CAST(ll.price.sale.price AS DOUBLE) AS price,
        (CAST(ll.price.sale.price AS DOUBLE)/CAST(ll.house_info.total_area AS INTEGER)) AS price_m2,
        CAST(ll.price.sale.condo_fee AS DOUBLE) AS condo_fee,
        CAST(ll.price.sale.iptu AS DOUBLE) AS iptu,
        CONCAT(UPPER(SUBSTR(CAST(ll.metadata.loft_property AS VARCHAR), 1, 1)), LOWER(SUBSTR(CAST(ll.metadata.loft_property AS VARCHAR), 2, 15))) AS is_platform_property,
        CASE
            WHEN ROW_NUMBER() OVER (PARTITION BY id ORDER BY CAST(CONCAT(CAST(year AS VARCHAR), '-', CAST(month AS VARCHAR), '-', CAST(day AS VARCHAR)) AS DATE) DESC) = 1 THEN 1
        END AS is_last_status,
        CAST(CONCAT(CAST(year AS VARCHAR), '-', CAST(month AS VARCHAR), '-', CAST(day AS VARCHAR)) AS DATE) AS ts_updated,
        FIRST_VALUE(CAST(CONCAT(CAST(year AS VARCHAR), '-', CAST(month AS VARCHAR), '-', CAST(day AS VARCHAR)) AS DATE)) OVER (PARTITION BY id ORDER BY CAST(CONCAT(CAST(year AS VARCHAR), '-', CAST(month AS VARCHAR), '-', CAST(day AS VARCHAR)) AS DATE) DESC) AS ts_last_publication,
        FIRST_VALUE(CAST(CONCAT(CAST(year AS VARCHAR), '-', CAST(month AS VARCHAR), '-', CAST(day AS VARCHAR)) AS DATE)) OVER (PARTITION BY 1 ORDER BY CAST(CONCAT(CAST(year AS VARCHAR), '-', CAST(month AS VARCHAR), '-', CAST(day AS VARCHAR)) AS DATE) DESC) AS ts_last_extraction
    FROM
        datalake_crawlers_clean_prod.loft_listings AS ll
),
qa_listings AS (
    WITH house_latlong_raw AS (
        SELECT
            id,
            CAST(lat AS VARCHAR) AS lat,
            CAST(lng AS VARCHAR) AS lng
        FROM
            datalake_ebdb_raw_prod.imovel
    )
    SELECT
        h.id,
        rh.lat,
        rh.lng,
        REGEXP_REPLACE(LOWER(address), 'avenida|rua|av.|#|&|1|2|3|4|5|6|7|8|9| da | de | do | das | dos ') AS qa_address_for_join,
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
),
dataset_distances AS (
    WITH  loft_listings_w_latlong AS (
        SELECT DISTINCT
            id_house_platform,
            lat,
            lng,
            loft_address_for_join
        FROM
            loft_listings_raw
        WHERE
            is_last_status = 1
    ),
    distance_loft_to_5a AS (
        SELECT
            l.id_house_platform,
            q.price_m2,
            (6371 * ACOS(COS(RADIANS(CAST(q.lat AS DOUBLE))) * COS(RADIANS(CAST(l.lat AS DOUBLE))) * COS(RADIANS(CAST(q.lng AS DOUBLE)) - RADIANS(CAST(l.lng AS DOUBLE))) + SIN(RADIANS(CAST(q.lat AS DOUBLE))) * SIN(RADIANS(CAST(l.lat AS DOUBLE))))) AS distance
        FROM
            loft_listings_w_latlong AS l
        JOIN
            qa_listings AS q
                ON (6371 * ACOS(COS(RADIANS(CAST(q.lat AS DOUBLE))) * COS(RADIANS(CAST(l.lat AS DOUBLE))) * COS(RADIANS(CAST(q.lng AS DOUBLE)) - RADIANS(CAST(l.lng AS DOUBLE))) + SIN(RADIANS(CAST(q.lat AS DOUBLE))) * SIN(RADIANS(CAST(l.lat AS DOUBLE))))) <= 0.05
                AND LEVENSHTEIN_DISTANCE(q.qa_address_for_join, l.loft_address_for_join) <= 4
                OR (6371 * ACOS(COS(RADIANS(CAST(q.lat AS DOUBLE))) * COS(RADIANS(CAST(l.lat AS DOUBLE))) * COS(RADIANS(CAST(q.lng AS DOUBLE)) - RADIANS(CAST(l.lng AS DOUBLE))) + SIN(RADIANS(CAST(q.lat AS DOUBLE))) * SIN(RADIANS(CAST(l.lat AS DOUBLE))))) <= 0.01
    )
    SELECT
        id_house_platform AS id_house_platform,
        COUNT(id_house_platform) AS nearby_other_platform_houses,
        AVG(price_m2) AS avg_nearby_price_m2,
        AVG(distance) AS avg_distance
    FROM
        distance_loft_to_5a
    GROUP BY 1
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
        city_name AS city_for_loft,
        city_group AS city_group_for_loft
    FROM
        datalake_clean.ods_dim_region
    WHERE
        level = 'SubRegiao'
    GROUP BY 1, 2
    HAVING
        city_group != ''
),
loft_listings_w_correct_regions AS (
    SELECT
        ll.sk_house,
        ll.id_house,
        ll.id_house_platform,
        IF(r.id_neighborhood IS NULL, CAST(-1 AS BIGINT), r.id_neighborhood) AS id_neighborhood,
        ll.platform,
        IF(r.city IS NULL, ll.city, r.city) AS city,
        rcg.city_group_for_loft AS city_group,
        IF(r.neighborhood IS NULL, ll.neighborhood_loft, r.neighborhood) AS neighborhood,
        ll.neighborhood_loft,
        ll.state,
        ll.lat,
        ll.lng,
        ll.address,
        ll.zip_code,
        ll.st_number,
        ll.floors,
        ll.num_floors,
        ll.total_area,
        ll.bedrooms,
        ll.suites,
        ll.parking_spaces,
        ll.bathrooms,
        ll.year_built,
        ll.unit_type,
        ll.usage_type,
        ll.price,
        ll.price_m2,
        ll.condo_fee,
        ll.iptu,
        dd.nearby_other_platform_houses,
        dd.avg_nearby_price_m2,
        dd.avg_distance,
        ll.is_platform_property,
        ll.is_last_status,
        CASE
            WHEN ll.is_platform_property = 'True' THEN 'True'
            WHEN r.id_neighborhood IS NULL
                AND dd.nearby_other_platform_houses <= 1 THEN 'True'
            WHEN dd.nearby_other_platform_houses IS NULL THEN 'True'
            ELSE 'False'
        END AS is_exclusive,
        ll.ts_updated,
        ll.ts_last_extraction,
        ll.ts_last_publication
    FROM
        loft_listings_raw AS ll
    LEFT JOIN
        regions AS r
            ON ST_WITHIN(ST_POINT(CAST(ll.lng AS DOUBLE), CAST(ll.lat AS DOUBLE)), r.geometry)
    LEFT JOIN
        dataset_distances AS dd
            ON ll.id_house_platform = dd.id_house_platform
    LEFT JOIN
        regions_for_city_group AS rcg
            ON ll.city = rcg.city_for_loft
    WHERE
        ll.is_last_status = 1
),
full_dataset AS (
    WITH ids_duplicados AS (
        SELECT
            id_house
        FROM
            loft_listings_w_correct_regions
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
            neighborhood_loft,
            state,
            lat,
            lng,
            address,
            zip_code,
            st_number,
            floors,
            num_floors,
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
            loft_listings_w_correct_regions
        WHERE
            id_house IN (SELECT id_house FROM ids_duplicados)
            AND neighborhood = neighborhood_loft
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
        neighborhood_loft,
        state,
        lat,
        lng,
        address,
        st_number,
        zip_code,
        floors,
        num_floors,
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
        loft_listings_w_correct_regions
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
        neighborhood_loft,
        state,
        lat,
        lng,
        address,
        st_number,
        zip_code,
        floors,
        num_floors,
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
loft_listings_clean AS (
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
    nearby_other_platform_houses,
    avg_nearby_price_m2,
    avg_distance,
    is_platform_property,
    is_exclusive,
    ts_updated
FROM
    loft_listings_clean