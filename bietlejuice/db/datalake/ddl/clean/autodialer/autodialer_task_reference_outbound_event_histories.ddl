DROP TABLE datalake_clean.autodialer_task_reference_outbound_event_histories;

CREATE EXTERNAL TABLE datalake_clean.autodialer_task_reference_outbound_event_histories (
  index bigint,
  `_class` string,
  class string,
  created_at string,
  eventdate string,
  hosannalead_active string,
  hosannalead_agendado string,
  hosannalead_agendado_data string,
  hosannalead_agendado_hora string,
  hosannalead_campo01 string,
  hosannalead_campo02 string,
  hosannalead_campo03 string,
  hosannalead_campo04 string,
  hosannalead_codigo string,
  hosannalead_email string,
  hosannalead_fone01 string,
  hosannalead_hashtag string,
  hosannalead_nome string,
  hosannalead_prioridade string,
  id string,
  leadid string,
  parsedpayload_conf_mailingid string,
  parsedpayload_conf_responsecode string,
  parsedpayload_conf_sourceid string,
  parsedpayload_conf_sourcetype string,
  parsedpayload_fone string,
  parsedpayload_lead_active string,
  parsedpayload_lead_description string,
  parsedpayload_lead_leadid string,
  parsedpayload_lead_reason string,
  parsedpayload_lead_responsecode string,
  payload string,
  status string,
  task_id string,
  taskid string,
  taskreferenceeventorigin string,
  updated_at string)
PARTITIONED BY (
  dt_extraction string)
STORED AS PARQUET
LOCATION
  's3://5a-datalake/clean/autodialer/task_reference_outbound_event_histories/'

msck repair table datalake_clean.autodialer_task_reference_outbound_event_histories;