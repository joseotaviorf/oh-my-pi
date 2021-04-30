SELECT
    _id AS id,
    origemId AS id_origin,
    assigneeId AS id_assignee,
    imovelId AS id_house,
    openedById AS id_opened_by,
    inquilinoId AS id_tenant,
    negociacaoId AS id_negotiation,
    gerenteId AS id_manager,
    proprietarioId AS id_owner,
    destinatarioId AS id_receiver,
    __v AS version,
    actions,
    score,
    scoreFactor AS score_factor,
    nomeDestinatario AS receiver_name,
    comentario AS task_comment,
    origem AS origin,
    type,
    tipoDestinatario AS receiver_type,
    descricao AS description,
    fase AS phase,
    dataInicio AS start_date_object,
    origemData AS origin_date_object,
    realizadaEm AS completed_date_object,
    silenciadaAte AS silenced_until_date_object,
    dataCriacao AS created_date_object,
    followUpVisita AS visit_fup,
    CAST(dataFup AS DOUBLE) AS unix_fup,
    startedAt AS analyst_started,
    tags,
    metadata,
    resolvida AS is_resolved,
    DATE(dataVisita) AS dt_visit,
    year,
    month,
    day
FROM
    datalake_crm_raw.tasks
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}
