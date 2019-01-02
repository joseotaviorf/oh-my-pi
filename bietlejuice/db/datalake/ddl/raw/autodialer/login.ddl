DROP TABLE datalake_raw.autodialer_login;

CREATE EXTERNAL TABLE datalake_raw.autodialer_login (
  id int, 
  active string, 
  data string, 
  login string, 
  logout string, 
  duracao string, 
  ipaddress string, 
  macaddress string, 
  hardaddress string, 
  versao string, 
  controle int, 
  justificativa string, 
  agente_tipo int, 
  supervisor_id int, 
  easy_call_operacao_conf_id int, 
  easy_work_colaborador_conf_id int, 
  easy_call_empresa_conf_id int, 
  updated_at int)
ROW FORMAT SERDE 
  'org.openx.data.jsonserde.JsonSerDe' 
LOCATION
  's3://5a-datalake/raw/autodialer/login.gz/'
TBLPROPERTIES (
  'compressionType'='gzip')