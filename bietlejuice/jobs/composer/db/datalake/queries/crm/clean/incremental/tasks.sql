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
    followUpVisita AS visit_fup,
    startedAt AS analyst_started,
    tags,
    metadata,
    resolvida AS is_resolved,
    CAST(realizadaEm AS TIMESTAMP) AS ts_completed,
    CAST(dataVisita AS TIMESTAMP) AS ts_visit,
    CAST(silenciadaAte AS TIMESTAMP) AS ts_silenced_until,
    CAST(dataCriacao AS TIMESTAMP) AS ts_created,
    CAST(dataFup AS TIMESTAMP) AS ts_fup,
    year,
    month,
    day
FROM
    datalake_crm_raw.tasks
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}
