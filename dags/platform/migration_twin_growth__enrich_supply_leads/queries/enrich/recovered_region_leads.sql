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
all_polygons AS (
    SELECT
        id_region,
        polygon,
        explode(h3_polyfillash3(polygon, 12)) as cell,
        ts_updated
    FROM datalake_ebdb_clean.polygon_region
),
leads_recovered AS (
    SELECT 
        id_lead, 
        id_lead_ebdb,
        id_region,
        lng,
        lat,
        h3_longlatash3(lng, lat, 12) AS cell
    FROM 
        leads_without_region
    WHERE 
        id_region IS NULL
        AND lng IS NOT NULL
        AND lat IS NOT NULL
)

SELECT 
    l.id_lead, 
    l.id_lead_ebdb,
    p.id_region,
    l.cell,
    l.lng,
    l.lat,
    NOW() AS ts_updated
FROM 
    leads_recovered AS l
JOIN 
    all_polygons AS p
        USING (cell)
JOIN 
    datalake_region.region AS d
        ON (p.id_region = d.id)
            AND (d.level = 'SubRegiao')
            AND (d.city_group IS NOT NULL)
QUALIFY ROW_NUMBER() OVER (PARTITION BY l.id_lead ORDER BY p.ts_updated) = 1