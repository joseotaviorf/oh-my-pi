drop table if exists datalake_raw.crm_tasks;
create external table if not exists datalake_raw.crm_tasks (
  links string,
  score_factor string,
  fluxo_locacao_id string,
  actions string,
  data_inicio string,
  nome_destinatario string,
  realizada_em string,
  comentario string,
  origem_id string,
  assignee_id string,
  score string,
  origem string,
  data_visita string,
  type string,
  tipo_destinatario string,
  descricao string,
  fase string,
  silenciada_ate string,
  imovel_id string,
  assunto string,
  tags string,
  opened_by_id string,
  inquilino_id string,
  data_criacao string,
  negociacao_id string,
  origem_data string,
  gerente_id string,
  data_fup string,
  follow_up_visita string,
  metadata string,
  v string,
  proprietario_id string,
  destinatario_id string,
  id string,
  resolvida string
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
  'mapping.v'='__v',
  'mapping.fluxo_locacao_id'='fluxoLocacaoId',
  'mapping.nome_destinatario'='nomeDestinatario',
  'mapping.data_visita'='dataVisita',
  'mapping.tipo_destinatario'='tipoDestinatario',
  'mapping.silenciada_ate'='silenciadaAte',
  'mapping.imovel_id'='imovelId',
  'mapping.opened_by_id'='openedById',
  'mapping.inquilino_id'='inquilinoId',
  'mapping.data_criacao'='dataCriacao',
  'mapping.negociacao_id'='negociacaoId',
  'mapping.gerente_id'='gerenteId',
  'mapping.data_fup'='dataFup',
  'mapping.follow_up_visita'='followUpVisita',
  'mapping.proprietario_id'='proprietarioId',
  'mapping.destinatario_id'='destinatarioId'
)
location 's3://5a-datalake/raw/crm/tasks/'
;

