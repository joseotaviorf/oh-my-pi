select
  cast(origem_id as bigint) as origem_id,
  origem_data,
  cast(assignee_id as bigint) as assignee_id,
  cast(resolvida as boolean) as resolvida,
  score_factor,
  actions,
  data_inicio,
  cast(v as integer) as v,
  origem,
  cast(destinatario_id as bigint) as destinatario_id,
  id,
  type,
  realizada_em,
  metadata
from datalake_raw.crm_tasks_credit
where dt = '{partition_date}'
;