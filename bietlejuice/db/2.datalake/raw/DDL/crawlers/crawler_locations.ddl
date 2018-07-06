drop table if exists datalake_raw.crawler_locations;

create external table datalake_raw.crawler_locations (
	id string,
	website string,
	glat string,
	glng string,
	gcep string,
	gstreet string,
	gstreet_number string,
	gneighborhood string,
	gcity string,
	gstate string,
	location_type string,
	location_precision string,
	dt_gaddress string
)
row format serde 'org.apache.hadoop.hive.serde2.OpenCSVSerde'
with serdeproperties (
  'separatorChar' = ',',
  'quoteChar' = '\"'
)
location 's3://5a-datalake/raw/crawler_locations/'
tblproperties (
  'skip.header.line.count' = '1'
)
;