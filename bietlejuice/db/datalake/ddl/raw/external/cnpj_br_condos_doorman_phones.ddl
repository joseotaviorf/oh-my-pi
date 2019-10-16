drop table datalake_raw.cnpj_br_condos_doorman_phones

create external table datalake_raw.cnpj_br_condos_doorman_phones (
  uf string,
  municipio string,
  cep string,
  cnpj string,
  razao_social string,
  dt_situacao_cadastral string,
  hash string,
  processed string,
  phone_found string,
  message string,
  telefone_inseguro string,
  telefone_seguro string
)
row format serde 'org.apache.hadoop.hive.serde2.OpenCSVSerde'
with serdeproperties (
  'separatorChar' = ',',
  'quoteChar' = '\"'
)
location 's3://5a-datalake/raw/external/direct/cnpj_br_condos_doorman_phones/'
tblproperties (
  'skip.header.line.count' = '1'
)
;
