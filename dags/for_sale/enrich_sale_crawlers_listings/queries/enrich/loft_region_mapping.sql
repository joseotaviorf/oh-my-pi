WITH loft_listings_raw AS (
    SELECT
        CONCAT(id, 'Loft') AS id_house,
        id AS id_house_platform,
        address.neighborhood AS neighborhood_loft,
        geolocation.latitude AS lat,
        geolocation.longitude AS lng,
        CAST(CONCAT(CAST(year AS STRING), '-', CAST(month AS STRING), '-', CAST(day AS STRING)) AS DATE) AS dt_updated,
        year,
        month,
        day
    FROM
        datalake_crawlers_listings_clean.loft
    WHERE
        year = {year}
        AND month = {month}
        AND day = {day}
),
regions AS (
    SELECT
        r.id AS id_neighborhood,
        r.name AS neighborhood,
        ST_GeomFromText(polygon) AS geometry
    FROM
        datalake_ebdb_clean.polygon_region AS pr
    JOIN
        datalake_ebdb_clean.map_region AS r
            ON r.id = pr.id_region
    WHERE
        r.level = 'SubRegiao'
),
loft_listings_w_correct_region AS (
    SELECT
        ll.id_house,
        ll.id_house_platform,
        r.id_neighborhood,
        COALESCE(r.neighborhood, ll.neighborhood_loft) AS neighborhood,
        ll.neighborhood_loft,
        ll.dt_updated
    FROM
        loft_listings_raw AS ll
    LEFT JOIN
        regions AS r
            ON ST_WITHIN(ST_POINT(ll.lng, ll.lat), r.geometry)
)
SELECT
    id_house,
    id_house_platform,
    id_neighborhood,
    neighborhood,
    dt_updated,
    NOW() AS ts_load
FROM 
    loft_listings_w_correct_region
