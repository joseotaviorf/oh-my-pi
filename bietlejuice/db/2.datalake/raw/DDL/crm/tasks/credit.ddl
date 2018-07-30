drop table if exists datalake_raw.crm_tasks_credit;
create external table if not exists datalake_raw.crm_tasks_credit (
  origem_id string,
  origem_data string,
  assignee_id string,
  resolvida string,
  score_factor string,
  actions array<string>,
  data_inicio string,
  v string,
  origem string,
  destinatario_id string,
  id string,
  type string,
  realizada_em string,
  metadata string
)
partitioned by (
  dt string
)
row format serde 'org.openx.data.jsonserde.JsonSerDe'
with serdeproperties (
  'ignore.malformed.json'='true',
  'mapping.assignee_id'='assigneeId',
  'mapping.data_inicio'='dataInicio',
  'mapping.destinatario_id'='destinatarioId',
  'mapping.id'='_id',
  'mapping.origem_data'='origemData',
  'mapping.origem_id'='origemId',
  'mapping.realizada_em'='realizadaEm',
  'mapping.score_factor'='scoreFactor',
  'mapping.v'='__v')
location 's3://5a-datalake/raw/crm/tasks/credit'
;

