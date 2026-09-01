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
-- EMR Spark 3.5 has no Sedona ST_WITHIN point-in-polygon support out of the box; use the
-- H3-index equi-join pattern (see growth/enrich_supply_leads/queries/enrich/recovered_region_leads.sql)
-- instead of the Databricks-only geospatial range join.
regions AS (
    SELECT
        r.id AS id_neighborhood,
        r.name AS neighborhood,
        EXPLODE(
            ST_H3CellIDs(ST_GeomFromText(pr.polygon), 12, false)
        ) AS cell
    FROM
        datalake_ebdb_clean.polygon_region AS pr
    JOIN
        datalake_ebdb_clean.map_region AS r
            ON r.id = pr.id_region
    WHERE
        r.level = 'SubRegiao'
),
listings_with_cell AS (
    SELECT
        id_house,
        id_house_platform,
        id_status,
        neighborhood,
        is_last_status,
        is_first_status,
        ts_first_publication,
        ts_updated,
        ts_last_extraction,
        ST_H3CellIDs(ST_POINT(CAST(lng AS DOUBLE), CAST(lat AS DOUBLE)), 12, false)[0] AS cell
    FROM
        listings_raw
),
region_matches_ranked AS (
    SELECT
        l.id_house,
        l.id_house_platform,
        l.id_status,
        l.neighborhood AS neighborhood_em_casa,
        r.id_neighborhood,
        r.neighborhood,
        l.is_last_status,
        l.is_first_status,
        l.ts_first_publication,
        l.ts_updated,
        l.ts_last_extraction,
        ROW_NUMBER() OVER (PARTITION BY l.id_status ORDER BY r.id_neighborhood) AS rn
    FROM
        listings_with_cell AS l
    LEFT JOIN
        regions AS r
            ON l.cell = r.cell
)
SELECT
    id_house,
    id_house_platform,
    id_status,
    COALESCE(id_neighborhood, -1) AS id_neighborhood,
    COALESCE(neighborhood, neighborhood_em_casa) AS neighborhood,
    neighborhood_em_casa,
    is_last_status,
    is_first_status,
    ts_first_publication,
    ts_updated,
    ts_last_extraction,
    NOW() AS ts_load
FROM
    region_matches_ranked
WHERE
    rn = 1
