drop table datalake_raw.neoway_owners

create external table datalake_raw.neoway_owners (
  cpf string,
  name string,
  street_names string,
  street_numbers string,
  complements string,
  neighborhoods string,
  cities string,
  states string,
  n_houses string,
  phone_numbers string
)
row format serde 'org.apache.hadoop.hive.serde2.OpenCSVSerde'
with serdeproperties (
  'separatorChar' = ',',
  'quoteChar' = '\"'
)
location 's3://5a-datalake/raw/external/owners/enriched/'
tblproperties (
  'skip.header.line.count' = '1'
)
;