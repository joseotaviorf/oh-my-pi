create external table {schema_name}.{table_name} (
  {columns}
)
row format serde 'org.apache.hadoop.hive.serde2.OpenCSVSerde'
with serdeproperties (
  'separatorChar' = ';',
  'quoteChar' = '\"'
)
location 's3://5a-datalake/{schema_folder}/files/{table_name}/'
tblproperties (
  'skip.header.line.count' = '1'
)
;