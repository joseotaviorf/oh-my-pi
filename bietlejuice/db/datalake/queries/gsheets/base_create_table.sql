create external table {schema_name}.gsheet_{table_name} (
  {columns}
)
row format serde 'org.openx.data.jsonserde.JsonSerDe'
with serdeproperties (
  'ignore.malformed.json'='true'
)
location 's3://5a-datalake/{schema_folder}/gsheets/{table_name}/'
;