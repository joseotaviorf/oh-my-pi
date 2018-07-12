drop table datalake_raw.crawled_cpf

create external table datalake_raw.crawled_cpf (
  abbreviation string,
  street_name string,
  street_number int,
  complement string,
  iptu_cod string,
  owners string
)
partitioned by (
  started_on_dd string
)
row format serde 'org.openx.data.jsonserde.JsonSerDe'
with serdeproperties ('mapping.owners' = 'cpf')
location 's3://5a-datalake/raw/crawled_cpfs/enriched'