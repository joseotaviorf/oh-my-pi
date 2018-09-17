drop table datalake_raw.street_type

create external table datalake_raw.street_type (
  abbreviation string,
  prefix string
)
partitioned by (
  city string
)
row format serde 'org.apache.hadoop.hive.serde2.OpenCSVSerde'
with serdeproperties (
  'separatorChar' = ','
)
stored as textfile
location 's3://5a-datalake/raw/external/logradouros/'

msck repair table datalake_raw.street_type