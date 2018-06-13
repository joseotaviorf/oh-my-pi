drop table if exists datalake_raw.crawled_exclusive;

create external table datalake_raw.crawled_exclusive (
	id string,
	url string,
	anunciante string,
	publicacao_5a_em string,
	atualizacao_externa_em string,
	pp_nome string,
	pp_telefone string,
	pp_email string,
	match_em string
)
row format serde 'org.apache.hadoop.hive.serde2.OpenCSVSerde'
with serdeproperties (
  'separatorChar' = ',',
  'quoteChar' = '\"'
)
location 's3://5a-datalake/raw/crawled_exclusives/'
tblproperties (
  'skip.header.line.count' = '1'
)
;