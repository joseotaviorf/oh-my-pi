drop table if exists datalake_raw.cnpj_br_condos

create external table datalake_raw.cnpj_br_condos (
  tipo_registro string,
  indicador_full_diario string,
  tipo_atualizacao string,
  cnpj string,
  matriz_filial string,
  razao_social string,
  nome_fantasia string,
  situacao_cadastral string,
  dt_situacao_cadastral string,
  motivo_situacao_cadastral string,
  nm_cidade_exterior string,
  cod_pais string,
  nm_pais string,
  cod_natureza_juridica string,
  dt_inicio_atividade string,
  cnae_fiscal string,
  tipo_logradouro string,
  logradouro string,
  numero string,
  complemento string,
  bairro string,
  cep string,
  uf string,
  cod_municipio string,
  municipio string,
  telefone_1 string,
  telefone_2 string,
  fax string,
  email string,
  quali_responsavel string,
  capital_social string,
  porte_empresa string,
  opcao_simples string,
  dt_opcao_simples string,
  dt_exclusao_simples string,
  opcao_mei string,
  situacao_especial string,
  dt_situacao_especial string,
  formatted_address string,
  comercial string,
  sem_numero string,
  hash string
)
row format serde 'org.apache.hadoop.hive.serde2.OpenCSVSerde'
with serdeproperties (
  'separatorChar' = ',',
  'quoteChar' = '\"'
)
location 's3://5a-datalake/raw/external/cnpj/br_condos/'
tblproperties (
  'skip.header.line.count' = '1'
)
;
