with
subregions as (
	select
		r.id as id_region,
		p.polygon,
		-- the format coming from origin needs some adjustment to be used by geo lib
        replace(
          replace(
            replace(
              -- the expected are comma separated values
              polygon, ' ', ','
            )
            -- the polygon definition is not necessary when converting to polygon
            -- thus removing keyword and parenthesis from POLYGON definition
            , 'POLYGON((', ''
          )
          , '))', ''
        ) as formatted_polygon
	from datalake_region.region r
	left join datalake_ebdb_clean.polygon_region p
		on p.id_region = r.id
	where r.level = 'SubRegiao'
),
features as (
    with geo_properties as (
		select
			"Feature" as type,
			ST_AsGeoJSON(
			    ST_PolygonFromText(formatted_polygon, ',')
			) as geometry,
            to_json(named_struct('sk_region', id_region, 'poligono', polygon)) as properties
		from subregions sr
		where polygon is not null
	)
	select
		'FeatureCollection' as type,
        collect_list(
         to_json(named_struct('type', type, 'geometry', geometry, 'properties', properties))
         )
        as features
	from geo_properties gp
 )
select
	to_json(named_struct('type', type, 'features', features))
from features f
