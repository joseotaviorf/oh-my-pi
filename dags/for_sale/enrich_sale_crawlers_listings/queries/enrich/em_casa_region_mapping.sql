WITH listings_raw AS (
    SELECT
        CONCAT(id, 'Emcasa') AS id_house,
        id AS id_house_platform,
        CONCAT(id, 'Emcasa', CAST(ROW_NUMBER() OVER (PARTITION BY CONCAT(id, 'Emcasa') ORDER BY CAST(CONCAT(CAST(year AS STRING), '-', CAST(month AS STRING), '-', CAST(day AS STRING)) AS DATE)) AS STRING)) AS id_status,
        address.neighborhood AS neighborhood,
        geolocation.latitude AS lat,
        geolocation.longitude AS lng,
        CASE
            WHEN ROW_NUMBER() OVER (PARTITION BY id ORDER BY CAST(CONCAT(CAST(year AS STRING), '-', CAST(month AS STRING), '-', CAST(day AS STRING)) AS DATE) DESC) = 1 THEN TRUE 
            ELSE FALSE
        END AS is_last_status,
        CASE
            WHEN ROW_NUMBER() OVER (PARTITION BY id ORDER BY CAST(CONCAT(CAST(year AS STRING), '-', CAST(month AS STRING), '-', CAST(day AS STRING)) AS DATE)) = 1 THEN TRUE 
            ELSE FALSE
        END AS is_first_status,
        CAST(CONCAT(CAST(year AS STRING), '-', CAST(month AS STRING), '-', CAST(day AS STRING)) AS DATE) AS ts_updated,
        FIRST_VALUE(CAST(CONCAT(CAST(year AS STRING), '-', CAST(month AS STRING), '-', CAST(day AS STRING)) AS DATE)) OVER (PARTITION BY id ORDER BY CAST(CONCAT(CAST(year AS STRING), '-', CAST(month AS STRING), '-', CAST(day AS STRING)) AS DATE)) AS ts_first_publication,
        FIRST_VALUE(CAST(CONCAT(CAST(year AS STRING), '-', CAST(month AS STRING), '-', CAST(day AS STRING)) AS DATE)) OVER (PARTITION BY 1 ORDER BY CAST(CONCAT(CAST(year AS STRING), '-', CAST(month AS STRING), '-', CAST(day AS STRING)) AS DATE) DESC) AS ts_last_extraction,
        year,
        month,
        day
    FROM
        datalake_crawlers_listings_clean.em_casa
    WHERE
        year = {year}
        AND month = {month}
        AND day = {day}
),
regions AS (
    SELECT
        r.id AS id_neighborhood,
        r.name AS neighborhood,
        ST_GeomFromText(pr.polygon) AS geometry
    FROM
        datalake_ebdb_clean.polygon_region AS pr
    JOIN
        datalake_ebdb_clean.map_region AS r
            ON r.id = pr.id_region
    WHERE
        r.level = 'SubRegiao'
)
SELECT
    l.id_house,
    l.id_house_platform,
    l.id_status,
    COALESCE(r.id_neighborhood, -1) AS id_neighborhood,
    COALESCE(r.neighborhood, l.neighborhood) AS neighborhood,
    l.neighborhood AS neighborhood_em_casa,
    l.is_last_status,
    l.is_first_status,
    l.ts_first_publication,
    l.ts_updated,
    l.ts_last_extraction,
    NOW() AS ts_load
FROM
    listings_raw AS l
LEFT JOIN
    regions AS r
        ON ST_WITHIN(ST_POINT(CAST(l.lng AS DOUBLE), CAST(l.lat AS DOUBLE)), r.geometry)
