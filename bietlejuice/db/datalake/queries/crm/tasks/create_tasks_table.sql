with json_entries as (
  select
    json_parse(task_entry) as task_entry,
    dt
  from datalake_raw.crm_tasks
)
select
  cast(json_extract(task_entry, '$.scoreFactor') as integer) as score_factor,
  cast(cast(json_extract(task_entry, '$.fluxoLocacaoId') as double) as bigint) as id_rent_flow,
  json_format(json_extract(task_entry, '$.actions')) as actions,
  replace(json_format(json_extract(task_entry, '$.dataInicio')), '"') as ts_start,
  replace(json_format(json_extract(task_entry, '$.nomeDestinatario')), '"') as receiver_name,
  replace(json_format(json_extract(task_entry, '$.realizadaEm')), '"') as ts_completed,
  replace(json_format(json_extract(task_entry, '$.comentario')), '"') as "comment",
  cast(cast(json_extract(task_entry, '$.origemId') as double) as bigint) as id_origin,
  cast(cast(json_extract(task_entry, '$.assigneeId') as double) as bigint) as id_assignee,
  json_format(json_extract(task_entry, '$.score')) as score,
  replace(json_format(json_extract(task_entry, '$.origem')), '"') as origin,
  replace(json_format(json_extract(task_entry, '$.dataVisita')), '"') as ts_visit,
  replace(json_format(json_extract(task_entry, '$.type')), '"') as type,
  replace(json_format(json_extract(task_entry, '$.tipoDestinatario')), '"') as receiver_type,
  replace(json_format(json_extract(task_entry, '$.descricao')), '"') as description,
  replace(json_format(json_extract(task_entry, '$.fase')), '"') as phase,
  replace(json_format(json_extract(task_entry, '$.silenciadaAte')), '"') as ts_silenced_until,
  cast(cast(json_extract(task_entry, '$.imovelId') as double) as bigint) as id_house,
  replace(json_format(json_extract(task_entry, '$.assunto')), '"') as subject,
  replace(json_format(json_extract(task_entry, '$.tags')), '"') as tags,
  cast(cast(json_extract(task_entry, '$.openedById') as double) as bigint) as id_opened_by,
  cast(cast(json_extract(task_entry, '$.inquilinoId') as double) as bigint) as id_tenant,
  replace(json_format(json_extract(task_entry, '$.dataCriacao')), '"') as ts_created,
  cast(cast(json_extract(task_entry, '$.negociacaoId') as double) as bigint) as id_negotiation,
  replace(json_format(json_extract(task_entry, '$.origemData')), '"') as ts_origin,
  cast(cast(json_extract(task_entry, '$.gerenteId') as double) as bigint) as id_manager,
  replace(json_format(json_extract(task_entry, '$.dataFup')), '"') as ts_fup,
  replace(json_format(json_extract(task_entry, '$.followUpVisita')), '"') as visit_fup,
  json_format(json_extract(task_entry, '$.metadata')) as metadata,
  cast(cast(json_extract(task_entry, '$.__v') as double) as integer) as v,
  cast(cast(json_extract(task_entry, '$.proprietarioId') as double) as bigint) as id_owner,
  cast(cast(json_extract(task_entry, '$.destinatarioId') as double) as bigint) as id_receiver,
  replace(json_format(json_extract(task_entry, '$._id')), '"') as id,
  cast(json_extract(task_entry, '$.resolvida') as boolean) as resolved,
  dt
from json_entries
where dt = '__PARTITION_DATE__'
;