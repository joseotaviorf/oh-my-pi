WITH leads_without_region AS (
    SELECT
        hl.id AS id_lead,
        hl.id_lead_ebdb,
        COALESCE(a.region, ebdb_lead.id_region) AS id_region,
        COALESCE(a.lng, ebdb_lead.lng) AS lng,
        COALESCE(a.lat, ebdb_lead.lat) AS lat
    FROM
        datalake_rene_descartes_clean.house_lead AS hl
    LEFT JOIN
        datalake_rene_descartes_clean.address AS a -- Getting id_region
            ON (hl.id_address = a.id)
    LEFT JOIN
        datalake_ebdb_clean.lead AS ebdb_lead -- Getting id_region
            ON (hl.id_lead_ebdb = ebdb_lead.id)
    WHERE
        DATE(hl.ts_created) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
),
-- Filter SubRegiao before H3 explode to avoid materializing cells for unused polygons.
all_polygons AS (
    SELECT
        pr.id_region,
        pr.polygon,
        EXPLODE(
            ST_H3CellIDs(ST_GeomFromText(pr.polygon), 12, false)
        ) AS cell,
        pr.ts_updated
    FROM
        datalake_ebdb_clean.polygon_region AS pr
    INNER JOIN
        datalake_region.region AS d
            ON pr.id_region = d.id
                AND d.level = 'SubRegiao'
                AND d.city_group IS NOT NULL
),
leads_recovered AS (
    SELECT
        id_lead,
        id_lead_ebdb,
        id_region,
        lng,
        lat,
        ST_H3CellIDs(ST_Point(lng, lat), 12, false)[0] AS cell
    FROM
        leads_without_region
    WHERE
        id_region IS NULL
        AND lng IS NOT NULL
        AND lat IS NOT NULL
),
ranked AS (
    SELECT
        l.id_lead,
        l.id_lead_ebdb,
        p.id_region,
        l.cell,
        l.lng,
        l.lat,
        NOW() AS ts_updated,
        ROW_NUMBER() OVER (PARTITION BY l.id_lead ORDER BY p.ts_updated) AS rn
    FROM
        leads_recovered AS l
    INNER JOIN
        all_polygons AS p
            USING (cell)
)
SELECT
    id_lead,
    id_lead_ebdb,
    id_region,
    cell,
    lng,
    lat,
    ts_updated
FROM
    ranked
WHERE
    rn = 1
