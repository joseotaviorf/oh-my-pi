create external table {schema_name}.gsheets_{table_name} (
  {columns}
)
row format serde 'org.openx.data.jsonserde.JsonSerDe'
with serdeproperties (
  'ignore.malformed.json'='true'
)
location 's3://{bucket}/{schema_folder}/gsheets/{table_name}/'
;