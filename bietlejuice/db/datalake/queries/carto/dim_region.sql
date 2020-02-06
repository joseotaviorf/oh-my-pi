SELECT
	r.sk_region,
	r.id,
	r.level,
	r.name,
	r.macro_id,
	r.macro_name,
	r.city_id,
	r.city_name,
	r.city_group,
	r.city_ddd,
	r.region_code,
	r.region_code_deprecated,
	r.region_code_inspector,
	r.short_region_name,
	r.greater_region,
	r.regional,
	r.regional_deprecated,
	r.tier,
	r.dt_created,
	r.dt_updated,
	r.dt_timestamp,
	r.dt_first_property_created,
	r.dt_first_booking,
	p.poligono,
	CURRENT_TIMESTAMP AS carto_ts_load
FROM datalake_clean.ods_dim_region r
LEFT JOIN datalake_raw.ebdb_poligonoregiao p ON r.sk_region = p.regiao_id
WHERE level = 'SubRegiao'
