drop table if exists datalake_raw.inside_sales_target;

create external table datalake_raw.inside_sales_target (
  canal string,
  nome string,
  id string,
  opportunnity_target string,
  listing_target string,
  team_leader string,
  team_leader_id string,
  manager string,
  manager_id string
)
row format serde 'org.apache.hadoop.hive.serde2.OpenCSVSerde'
with serdeproperties (
  'separatorChar' = ';',
  'quoteChar' = '\"',
  'mapping.canal'='Canal',
  'mapping.nome'='Nome',
  'mapping.id'='ID',
  'mapping.opportunnity_target'='Opportunity',
  'mapping.listing_target'='Listing',
  'mapping.team_leader'='TL',
  'mapping.team_leader_id'='TL ID',
  'mapping.manager'='Manager',
  'mapping.manager_id'='Manager ID'
)
location 's3://5a-datalake/raw/files/inside_sales_target/'
tblproperties (
  'skip.header.line.count' = '1'
)
;