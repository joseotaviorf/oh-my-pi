with json_entries as (
  select
    json_parse(task_entry) as task_entry,
    dt
  from datalake_raw.crm_tasks
  where dt = '__PARTITION_DATE__'
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
  cast(json_extract(task_entry, '$.origemId') as varchar) as id_origin,
  cast(json_extract(task_entry, '$.assigneeId') as varchar) as id_assignee,
  json_format(json_extract(task_entry, '$.score')) as score,
  cast(coalesce(json_extract(task_entry, '$.origem'),
                json_extract(task_entry, '$.metadata.origem')) 
      as varchar) as origin,
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
  -- since we don't have a corresponding SQL VARCHAR value, we need to serializes the input to JSON and then to VARCHAR
  json_format(json_extract(task_entry, '$.startedAt')) as analyst_started_list,
  cast(coalesce(json_extract(task_entry, '$.metadata.imovelId'),
                json_extract(task_entry, '$.imovelId'),
                json_extract(task_entry, '$.metadata.imovel.id'))
      as varchar) as id_house,
  cast(json_extract(task_entry, '$.metadata.assunto') as varchar) as subject,
  json_format(json_extract(task_entry, '$.tags')) as tags,
  cast(json_extract(task_entry, '$.openedById') as varchar) as id_opened_by,
  cast(coalesce(json_extract(task_entry, '$.inquilinoId'),
                json_extract(task_entry, '$.metadata.inquilinoId'))  
      as varchar) as id_tenant,
  cast(coalesce(json_extract(task_entry, '$.dataCriacao'),
                json_extract(task_entry, '$.metadata.dataCriacao'))
      as varchar) as ts_created,
  cast(coalesce(json_extract(task_entry, '$.negociacaoId'),
                json_extract(task_entry, '$.metadata.negociacaoId'))
      as varchar) as id_negotiation,
  cast(json_extract(task_entry, '$.origemData') as varchar) as ts_origin,
  cast(coalesce(json_extract(task_entry, '$.gerenteId'), 
                json_extract(task_entry, '$.metadata.gerenteId'))
      as varchar) as id_manager,
  cast(coalesce(json_extract(task_entry, '$.dataFup'),
                json_extract(task_entry, '$.metadata.dataFup')) 
      as varchar) as ts_fup,
  cast(json_extract(task_entry, '$.followUpVisita') as varchar) as visit_fup,
  json_format(json_extract(task_entry, '$.metadata')) as metadata,
  cast(json_extract(task_entry, '$.__v') as varchar) as v,
  cast(coalesce(json_extract(task_entry, '$.proprietarioId'),
                json_extract(task_entry, '$.metadata.proprietarioId'), 
                json_extract(task_entry, '$.metadata.house.proprietarioId'),
                json_extract(task_entry, '$.metadata.imovel.proprietarioId'),
                json_extract(task_entry, '$.metadata.contrato.imovel.proprietarioId'))
      as varchar) as id_owner,
  cast(coalesce(json_extract(task_entry, '$.metadata.destinatarioId'),
                json_extract(task_entry, '$.destinatarioId'),
                json_extract(task_entry, '$.metadata.destinatario.id')) 
      as varchar) as id_receiver,
  cast(json_extract(task_entry, '$._id') as varchar) as id,
  cast(json_extract(task_entry, '$.resolvida') as varchar) as resolved,
  dt
from json_entries
;