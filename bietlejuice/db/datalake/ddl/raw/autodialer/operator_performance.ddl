DROP TABLE datalake_raw.autodialer_operator_performance;

CREATE EXTERNAL TABLE datalake_raw.autodialer_operator_performance (
  id int, 
  ukey bigint, 
  agente_cod int, 
  agente_descricao string, 
  supervisor_cod int, 
  supervisor_descricao string, 
  primeiro_login_data string, 
  primeiro_login_hora string, 
  ultimo_login_data string, 
  ultimo_login_hora string, 
  intervalo_entre_primeiro_e_ultimo_login int, 
  quantidade_eventos int, 
  total_tempo_logado_confirmado int, 
  media_tempo_logado_confirmado int, 
  ativo_discadas_qtd int, 
  ativo_atendidas_qtd int, 
  ativo_tempo_total_falado int, 
  receptivo_atendidas_qtd int, 
  receptivo_tempo_total_falado int, 
  total_pausa_manual int, 
  total_pausa_sistema int, 
  total_pausa int, 
  rna_agente int, 
  rna_sistema int, 
  rna_ramal int, 
  easy_call_empresa_conf_id int)
ROW FORMAT SERDE 
  'org.openx.data.jsonserde.JsonSerDe' 
LOCATION
  's3://5a-datalake/raw/autodialer/operator_performance.gz/'
TBLPROPERTIES (
  'compressionType'='gzip')