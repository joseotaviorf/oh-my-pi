SELECT
	CAST(city_census_id AS INTEGER) AS id_city_census,
	CAST(crowding_area_id AS BIGINT) AS id_crowding_area,
	polygon,
	crowding_area_name,
	city_name,
	uf
FROM
	datalake_gsheets_raw.aglomerados_subnormais_2010_limites
