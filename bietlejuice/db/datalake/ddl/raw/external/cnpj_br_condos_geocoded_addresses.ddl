drop table datalake_raw.cnpj_br_condos_geocoded_addresses

create external table datalake_raw.cnpj_br_condos_geocoded_addresses (
  hash string,
  geocode string,
  geocode_hash string,
  google_formatted_address string,
  lat string,
  lng string,
  location_type string,
  place_id string,
  types string
)
row format serde 'org.apache.hadoop.hive.serde2.OpenCSVSerde'
with serdeproperties (
  'separatorChar' = ',',
  'quoteChar' = '\"'
)
location 's3://5a-datalake/raw/external/cnpj/br_condos_geocoded_addresses/'
tblproperties (
  'skip.header.line.count' = '1'
)
;
