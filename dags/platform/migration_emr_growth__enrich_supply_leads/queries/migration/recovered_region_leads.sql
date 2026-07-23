WITH leads_without_region AS (
  SELECT
    hl.id AS id_lead,
    hl.id_lead_ebdb,
    COALESCE(a.region, ebdb_lead.id_region) AS id_region,
    COALESCE(a.lng, ebdb_lead.lng) AS lng,
    COALESCE(a.lat, ebdb_lead.lat) AS lat
  FROM datalake_rene_descartes_clean.house_lead AS hl
  LEFT JOIN datalake_rene_descartes_clean.address AS a /* Getting id_region */
    ON (
      hl.id_address = a.id
    )
  LEFT JOIN datalake_ebdb_clean.lead AS ebdb_lead /* Getting id_region */
    ON (
      hl.id_lead_ebdb = ebdb_lead.id
    )
  WHERE
    CAST(hl.ts_created AS DATE) BETWEEN CAST('{load_start_date}' AS DATE) AND CAST('{load_end_date}' AS DATE)
), all_polygons AS (
  SELECT
    id_region,
    polygon,
    EXPLODE(H3_POLYFILLASH3(polygon, 12)) AS cell,
    ts_updated
  FROM datalake_ebdb_clean.polygon_region
), leads_recovered AS (
  SELECT
    id_lead,
    id_lead_ebdb,
    id_region,
    lng,
    lat,
    H3_LONGLATASH3(lng, lat, 12) AS cell
  FROM leads_without_region
  WHERE
    id_region IS NULL AND NOT lng IS NULL AND NOT lat IS NULL
)
SELECT
  id_lead,
  id_lead_ebdb,
  id_region,
  cell,
  lng,
  lat,
  ts_updated
FROM (
  SELECT
    l.id_lead,
    l.id_lead_ebdb,
    p.id_region,
    l.cell,
    l.lng,
    l.lat,
    NOW() AS ts_updated,
    ROW_NUMBER() OVER (PARTITION BY l.id_lead ORDER BY NOW()) AS _w
  FROM leads_recovered AS l
  JOIN all_polygons AS p
    USING (cell)
  JOIN datalake_region.region AS d
    ON (
      p.id_region = d.id
    )
    AND (
      d.level = 'SubRegiao'
    )
    AND (
      NOT d.city_group IS NULL
    )
) AS _t
WHERE
  _w = 1