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
-- EMR Spark 3.5 has no Sedona ST_WITHIN point-in-polygon support out of the box; use the
-- H3-index equi-join pattern (see growth/enrich_supply_leads/queries/enrich/recovered_region_leads.sql)
-- instead of the Databricks-only geospatial range join.
regions AS (
    SELECT
        r.id AS id_neighborhood,
        r.name AS neighborhood,
        EXPLODE(
            ST_H3CellIDs(ST_GeomFromText(polygon), 12, false)
        ) AS cell
    FROM
        datalake_ebdb_clean.polygon_region AS pr
    JOIN
        datalake_ebdb_clean.map_region AS r
            ON r.id = pr.id_region
    WHERE
        r.level = 'SubRegiao'
),
loft_listings_with_cell AS (
    SELECT
        id_house,
        id_house_platform,
        neighborhood_loft,
        dt_updated,
        ST_H3CellIDs(ST_POINT(lng, lat), 12, false)[0] AS cell
    FROM
        loft_listings_raw
),
loft_listings_w_correct_region_ranked AS (
    SELECT
        ll.id_house,
        ll.id_house_platform,
        r.id_neighborhood,
        COALESCE(r.neighborhood, ll.neighborhood_loft) AS neighborhood,
        ll.neighborhood_loft,
        ll.dt_updated,
        ROW_NUMBER() OVER (PARTITION BY ll.id_house ORDER BY r.id_neighborhood) AS rn
    FROM
        loft_listings_with_cell AS ll
    LEFT JOIN
        regions AS r
            ON ll.cell = r.cell
)
SELECT
    id_house,
    id_house_platform,
    id_neighborhood,
    neighborhood,
    dt_updated,
    NOW() AS ts_load
FROM
    loft_listings_w_correct_region_ranked
WHERE
    rn = 1
