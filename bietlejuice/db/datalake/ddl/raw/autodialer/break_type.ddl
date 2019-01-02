DROP TABLE datalake_raw.autodialer_break_type;

CREATE EXTERNAL TABLE datalake_raw.autodialer_break_type (
  id int,
  active string,
  descricao string,
  tipo string,
  nr17 string,
  acao string,
  permite_chamada_ativa_act string,
  permite_receber_transferencia_act string,
  bloqueio_act string,
  easy_call_empresa_conf_id int,
  dash_cor string)
ROW FORMAT SERDE
  'org.openx.data.jsonserde.JsonSerDe'
LOCATION
  's3://5a-datalake/raw/autodialer/break_type.gz/'
TBLPROPERTIES (
  'compressionType'='gzip')