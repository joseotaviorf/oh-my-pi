drop table datalake_raw.external_iptu_owners

create external table datalake_raw.external_iptu_owners (
  uf string,
  municipio string,
  inscricao string,
  utilizacao string,
  tipo string,
  endereco_completo string,
  endereco_logradouro_num_comp string,
  endereco_logradouro string,
  endereco_numero string,
  endereco_complemento string,
  endereco_bairro string,
  endereco_cep string,
  valor_venal string,
  proprietario_nome string,
  proprietario_nome_norm string,
  proprietario_tipo string,
  proprietario_match_tipo string,
  proprietario_cpf_cnpj string,
  proprietario_obito string,
  direct_id string,
  data_consulta string
)
row format serde 'org.apache.hadoop.hive.serde2.OpenCSVSerde'
with serdeproperties (
  'separatorChar' = ';'
)
location 's3://5a-datalake/raw/external/direct/iptu_owners/'
tblproperties (
  'skip.header.line.count' = '1'
)
;
