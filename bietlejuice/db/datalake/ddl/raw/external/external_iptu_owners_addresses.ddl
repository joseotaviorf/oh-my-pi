drop table datalake_raw.external_iptu_owners_addresses

create external table datalake_raw.external_iptu_owners_addresses (
  uf string,
  municipio string,
  inscricao string,
  direct_id string,
  formatted_address string,
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
  'separatorChar' = ','
)
location 's3://5a-datalake/raw/external/direct/iptu_owners_addresses/'
tblproperties (
  'skip.header.line.count' = '1'
)
;
