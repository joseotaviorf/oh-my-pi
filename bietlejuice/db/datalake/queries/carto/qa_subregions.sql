SELECT r.*, p.poligono AS geometry
FROM datalake_clean.ods_dim_region r
LEFT JOIN datalake_raw.ebdb_poligonoregiao p ON r.sk_region = p.regiao_id
WHERE level = 'SubRegiao'
