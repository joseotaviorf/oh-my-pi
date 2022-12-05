WITH subregions AS (
	SELECT
		r.id AS id_region,
		p.polygon,
        REPLACE(REPLACE(REPLACE(
			polygon
			, ' ', ',')  -- expected comma separated values
            , 'POLYGON((', '') -- removing `POLYGON` word and parenthesis, as they're unnecessary when converting to polygon
          	, '))', ''
		) AS formatted_polygon
	FROM
		datalake_region.region r
	LEFT JOIN
		datalake_ebdb_clean.polygon_region p
			ON p.id_region = r.id
	WHERE
		r.level = 'SubRegiao'
),
geo_properties AS (
	SELECT
		"Feature" AS type,
		ST_AsGeoJSON(ST_PolygonFromText(formatted_polygon, ',')) AS geometry,
		TO_JSON(NAMED_STRUCT('sk_region', id_region, 'poligono', polygon)) AS properties
	FROM
		subregions
	WHERE
		polygon IS NOT NULL
),
features AS (
	SELECT
		'FeatureCollection' AS type,
        COLLECT_LIST(TO_JSON(NAMED_STRUCT('type', type, 'geometry', geometry, 'properties', properties))) AS features
	FROM
		geo_properties
)
SELECT
	TO_JSON(NAMED_STRUCT('type', type, 'features', features))
FROM
	features
