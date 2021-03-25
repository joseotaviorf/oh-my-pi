WITH cte_tasks AS(
  SELECT 
    *,
    FROM_JSON(metadata,
      'fluxoLocacaoId STRING,
      destinatario STRUCT<nome: STRING, id: STRING>, 
      comentario STRING,
      origem STRING,
      dataVisita STRING,
      descricao STRING,
      fase STRING,
      imovelId STRING,
      imovel STRUCT<id: STRING, proprietarioId: STRING>,
      assunto STRING,
      inquilinoId STRING,
      dataCriacao STRING,
      negociacaoId STRING,
      gerenteId STRING,
      workgroupId STRING,
      contractId STRING,
      dataFup STRING,
      estadoId STRING,
      proprietarioId STRING,
      house STRUCT<proprietarioId: STRING>,
      contrato STRUCT<imovel: STRUCT<proprietarioId: STRING>>,
      destinatarioId STRING'
    ) AS json_metadata
  FROM
    datalake_crm_clean.tasks
  WHERE
    year = {year}
    AND month = {month}
    AND day = {day}
)
SELECT 
    GET_JSON_OBJECT(REPLACE(id, '$', ''),"$.oid") AS id,
    json_metadata.fluxoLocacaoId AS id_rent_flow,
    id_origin,
    id_assignee,
    COALESCE(json_metadata.imovelId, id_house, json_metadata.imovel.id) AS id_house,
    COALESCE(
      id_owner, 
      json_metadata.proprietarioId, 
      json_metadata.house.proprietarioId, 
      json_metadata.imovel.proprietarioId, 
      json_metadata.contrato.imovel.proprietarioId
    ) AS id_owner,
    id_opened_by,
    COALESCE(
      json_metadata.destinatarioId,
      id_receiver,
      json_metadata.destinatario.id
    ) AS id_receiver,
    COALESCE(id_negotiation, json_metadata.negociacaoId) AS id_negotiation,
    COALESCE(id_tenant, json_metadata.inquilinoId) AS id_tenant,
    COALESCE(id_manager, json_metadata.gerenteId) AS id_manager,
    json_metadata.workgroupId AS id_workgroup,
    json_metadata.contractId AS id_contract,
    json_metadata.estadoId AS id_state,
    version,
    score_factor,
    REPLACE(COALESCE(receiver_name,json_metadata.destinatario.nome), ',', '') AS receiver_name,
    COALESCE(task_comment,json_metadata.comentario) AS task_comment,
    score,
    COALESCE(origin, json_metadata.origem) AS origin,
    type,
    receiver_type,
    COALESCE(json_metadata.descricao, description) AS description,
    COALESCE(json_metadata.fase, phase) AS phase,
    visit_fup,
    json_metadata.assunto AS subject,
    tags,
    is_resolved,
    ts_completed,
    ts_silenced_until,
    CAST(GET_JSON_OBJECT(REPLACE(start_date_object, '$', ''), '$.date') AS TIMESTAMP) AS ts_start,
    CAST(COALESCE(ts_visit, json_metadata.dataVisita) AS TIMESTAMP) AS ts_visit,
    CAST(COALESCE(ts_created, json_metadata.dataCriacao) AS TIMESTAMP) AS ts_created,
    CAST(GET_JSON_OBJECT(REPLACE(origin_date_object, '$', ''), '$.date') AS TIMESTAMP) AS ts_origin,
    CAST(COALESCE(ts_fup, json_metadata.dataFup) AS TIMESTAMP) AS ts_fup,
    year,
    month,
    day
FROM 
    cte_tasks