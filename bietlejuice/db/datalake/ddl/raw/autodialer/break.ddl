DROP TABLE datalake_raw.autodialer_break;

CREATE EXTERNAL TABLE datalake_raw.autodialer_break (
  id int,
  active string,
  data string,
  pause string,
  unpause string,
  duracao string,
  restritiva_act string,
  justificativa string,
  desbloqueado_por int,
  supervisor_id string,
  controle int,
  easy_call_operacao_conf_id int,
  easy_call_empresa_conf_id int,
  easy_work_colaborador_conf_id int,
  easy_call_operacao_pausa_conf_id int,
  updated_at int )
ROW FORMAT SERDE 
  'org.openx.data.jsonserde.JsonSerDe' 
LOCATION
  's3://5a-datalake/raw/autodialer/break.gz/'
TBLPROPERTIES (
  'compressionType'='gzip')