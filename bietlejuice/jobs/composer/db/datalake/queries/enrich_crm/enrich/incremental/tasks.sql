WITH cte_tasks AS(
  SELECT 
    *,
    FROM_JSON(metadata,
     'fluxoLocacaoId STRING,
      destinatario STRING, 
      comentario STRING,
      origem STRING,
      dataVisita DATE,
      descricao STRING,
      fase STRING,
      imovelId STRING,
      imovel STRING,
      assunto STRING,
      inquilinoId STRING,
      dataCriacao STRING,
      negociacaoId STRING,
      gerenteId STRING,
      workgroupId STRING,
      contract_id STRING,
      contractId STRING,
      dataFup STRING,
      estadoId STRING,
      proprietarioId STRING,
      house STRING,
      contrato STRING,
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
    COALESCE(json_metadata.imovelId, id_house, GET_JSON_OBJECT(json_metadata.imovel, "$.id")) AS id_house,
    COALESCE(
      id_owner, 
      json_metadata.proprietarioId,
      GET_JSON_OBJECT(json_metadata.house, "$.proprietarioId"),
      GET_JSON_OBJECT(json_metadata.imovel, "$.proprietarioId"),
      GET_JSON_OBJECT(GET_JSON_OBJECT(json_metadata.contrato, "$.imovel"), "$.proprietarioId")
    ) AS id_owner,
    id_opened_by,
    COALESCE(
      json_metadata.destinatarioId,
      id_receiver,
      GET_JSON_OBJECT(json_metadata.destinatario, "$.id")
    ) AS id_receiver,
    COALESCE(id_negotiation, json_metadata.negociacaoId) AS id_negotiation,
    COALESCE(id_tenant, json_metadata.inquilinoId) AS id_tenant,
    COALESCE(id_manager, json_metadata.gerenteId) AS id_manager,
    json_metadata.workgroupId AS id_workgroup,
    COALESCE(json_metadata.contractId,json_metadata.contract_id) AS id_contract,
    json_metadata.estadoId AS id_state,
    CAST(version AS INTEGER) AS version,
    CAST(score_factor AS INTEGER) AS score_factor,
    REPLACE(COALESCE(receiver_name,GET_JSON_OBJECT(json_metadata.destinatario, "$.nome")), ',', '') AS receiver_name,
    GET_JSON_OBJECT(json_metadata.destinatario, "$.label") AS receiver_label,
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
    CAST(is_resolved AS BOOLEAN) AS is_resolved,
    CAST(GET_JSON_OBJECT(REPLACE(completed_date_object, '$', ''), '$.date') AS TIMESTAMP) AS ts_completed,
    CAST(GET_JSON_OBJECT(REPLACE(silenced_until_date_object, '$', ''), '$.date') AS TIMESTAMP) AS ts_silenced_until,
    CAST(GET_JSON_OBJECT(REPLACE(start_date_object, '$', ''), '$.date') AS TIMESTAMP) AS ts_start,
    DATE(COALESCE(dt_visit, json_metadata.dataVisita)) AS dt_visit,
    CAST(
      COALESCE(
        GET_JSON_OBJECT(REPLACE(created_date_object, '$', ''), '$.date'), 
        json_metadata.dataCriacao
      ) 
      AS TIMESTAMP
    ) AS ts_created,
    CAST(GET_JSON_OBJECT(REPLACE(origin_date_object, '$', ''), '$.date') AS TIMESTAMP) AS ts_origin,
    FROM_UNIXTIME(
      COALESCE(
        unix_fup/1000, 
        CAST(json_metadata.dataFup AS DOUBLE)/1000
      ), 
      'yyyy-MM-dd HH:mm:ss'
    ) AS ts_fup,
    year,
    month,
    day
FROM 
    cte_tasks