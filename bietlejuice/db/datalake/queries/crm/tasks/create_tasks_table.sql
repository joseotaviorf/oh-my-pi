with json_entries as (
  select
    json_parse(task_entry) as task_entry,
    dt
  from datalake_raw.crm_tasks
)
select
  cast(json_extract(task_entry, '$.scoreFactor') as varchar) as score_factor,
  cast(json_extract(task_entry, '$.metadata.fluxoLocacaoId') as varchar) as id_rent_flow,
  json_format(json_extract(task_entry, '$.actions')) as actions,
  cast(json_extract(task_entry, '$.dataInicio') as varchar) as ts_start,
  cast(coalesce(json_extract(task_entry, '$.nomeDestinatario'),
                json_extract(task_entry, '$.metadata.destinatario.nome')) 
      as varchar) as receiver_name,
  cast(json_extract(task_entry, '$.realizadaEm') as varchar) as ts_completed,
  cast(coalesce(json_extract(task_entry, '$.comentario'),
                json_extract(task_entry, '$.metadata.comentario'))
      as varchar) as "comment",
  cast(json_extract(json_parse(task_entry), '$.origemId') as varchar) as id_origin,
  cast(cast(json_extract(task_entry, '$.assigneeId') as double) as varchar) as id_assignee,
  json_format(json_extract(task_entry, '$.score')) as score,
  cast(coalesce(json_extract(task_entry, '$.dataVisita'),
                json_extract(task_entry, '$.metadata.dataVisita')) 
      as varchar) as ts_visit,
  cast(json_extract(task_entry, '$.type') as varchar) as type,
  cast(json_extract(task_entry, '$.tipoDestinatario') as varchar) as receiver_type,
  cast(coalesce(json_extract(task_entry, '$.metadata.descricao'),
                json_extract(task_entry, '$.descricao')) 
      as varchar) as "description",
  cast(coalesce(json_extract(task_entry, '$.metadata.fase'),
                json_extract(task_entry, '$.fase')) 
      as varchar) as phase,
  cast(json_extract(task_entry, '$.silenciadaAte') as varchar) as ts_silenced_until,
  cast(coalesce(json_extract(task_entry, '$.metadata.imovelId'),
                json_extract(task_entry, '$.imovelId'))
      as varchar) as id_house,
  cast(coalesce(json_extract(task_entry, '$.metadata.assunto') as varchar) as subject,
  json_format(coalesce(json_extract(task_entry, '$.tags'),
                       json_extract(task_entry, '%.metadata.tags'))) as tags,
  cast(json_extract(task_entry, '$.openedById') as varchar) as id_opened_by,
  cast(coalesce(json_extract(task_entry, '$.inquilinoId'),
                json_extract(task_entry, '$.metadata.inquilinoId'))  
      as varchar) as id_tenant,
  cast(json_extract(task_entry, '$.dataCriacao') as varchar) as ts_created,
  cast(cast(json_extract(task_entry, '$.negociacaoId') as double) as bigint) as id_negotiation,
  cast(json_extract(task_entry, '$.origemData') as varchar) as ts_origin,
  cast(cast(json_extract(task_entry, '$.gerenteId') as double) as bigint) as id_manager,
  cast(json_extract(task_entry, '$.dataFup') as varchar) as ts_fup,
  cast(json_extract(task_entry, '$.followUpVisita') as varchar) as visit_fup,
  json_format(json_extract(task_entry, '$.metadata')) as metadata,
  cast(cast(json_extract(task_entry, '$.__v') as double) as integer) as v,
  cast(cast(json_extract(task_entry, '$.proprietarioId') as double) as bigint) as id_owner,
  cast(cast(json_extract(task_entry, '$.destinatarioId') as double) as bigint) as id_receiver,
  cast(json_extract(task_entry, '$._id') as varchar) as id,
  cast(json_extract(task_entry, '$.resolvida') as boolean) as resolved,
  dt
from json_entries
where dt = '__PARTITION_DATE__'
;