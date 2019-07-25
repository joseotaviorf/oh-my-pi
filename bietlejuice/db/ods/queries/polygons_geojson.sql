with subregions as (
	select
		r.sk_region as sk_region,
		p.poligono as poligono
	from vw_dim_region r
	left join polygon_region p
		on p.regiao_id = r.id
	where r.level = 'SubRegiao'
),
features as (
	with geometries as (
		select
			'Feature' as type,
			ST_AsGeoJSON(poligono)::json As geometry,
			row_to_json(sr)
		from subregions sr
	)
	select
		'FeatureCollection' as type,
		array_to_json(array_agg(g)) as features
	from geometries g
)
select
	row_to_json(f)
from features f
;
