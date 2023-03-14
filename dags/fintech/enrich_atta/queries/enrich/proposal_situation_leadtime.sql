WITH log_union AS (
    (
        SELECT
            CAST(id AS STRING) AS id,
            id_proposal,
            id_current_status,
            id_previous_proposal_situation,
            id_current_proposal_situation,
            lag(ts_current_log) over(partition by id_proposal,id_current_status order by ts_current_log) as ts_previous_log,
            ts_current_log
        FROM
            datalake_atta_clean.log_isolve_v1
    )
    UNION
    (
        SELECT
            id,
            CAST(id_proposal AS INTEGER) AS id_proposal,
            CAST(GET_JSON_OBJECT(to, '$.Status') AS INTEGER) AS id_current_status,
            CAST(GET_JSON_OBJECT(from, '$.Situacao') AS INTEGER) AS id_previous_proposal_situation,
            CAST(GET_JSON_OBJECT(to, '$.Situacao') AS INTEGER) AS id_current_proposal_situation,
            CAST(GET_JSON_OBJECT(from, '$.DtUltAtu') AS TIMESTAMP) AS ts_previous_log,
            to_utc_timestamp(GET_JSON_OBJECT(to, '$.DtUltAtu') , 'UTC+3') AS ts_current_log
        FROM
            datalake_atta_clean.log_isolve_v2
        WHERE
            GET_JSON_OBJECT(to, '$.Status') IS NOT NULL
            AND type_operation = 'Proposta'
    )
    ),log_classified AS (
SELECT
        log.id_proposal,
        log.id_current_status,
        pre.proposal_status,
        log.id_previous_proposal_situation,
        CASE log.id_previous_proposal_situation
            WHEN 1 THEN 'Andamento'
            WHEN 2 THEN 'Aprovado'
            WHEN 3 THEN 'Pendente'
            WHEN 4 THEN 'Reprovado'
            WHEN 5 THEN 'Cancelada'
            WHEN 6 THEN 'Finalizada'
            WHEN 7 THEN 'Em Análise'
            WHEN 8 THEN 'Análise Atta'
            WHEN 9 THEN 'Análise Banco'
            WHEN 10 THEN 'Análise Banco Duvida'
        END AS proposal_previous_situation,
        CASE log.id_current_proposal_situation
            WHEN 1 THEN 'Andamento'
            WHEN 2 THEN 'Aprovado'
            WHEN 3 THEN 'Pendente'
            WHEN 4 THEN 'Reprovado'
            WHEN 5 THEN 'Cancelada'
            WHEN 6 THEN 'Finalizada'
            WHEN 7 THEN 'Em Análise'
            WHEN 8 THEN 'Análise Atta'
            WHEN 9 THEN 'Análise Banco'
            WHEN 10 THEN 'Análise Banco Duvida'
        END AS proposal_current_situation,
        log.ts_previous_log,
        log.ts_current_log,
        (bigint(unix_timestamp(ts_current_log)) - bigint(unix_timestamp(ts_previous_log)))/3600 as leadtime_situation,
        MIN(log.ts_current_log) OVER (PARTITION BY log.id_proposal, pre.proposal_status ORDER BY log.id_proposal, pre.proposal_status) AS min_ts_step,
        MAX(log.ts_current_log) OVER (PARTITION BY log.id_proposal, pre.proposal_status ORDER BY log.id_proposal, pre.proposal_status) AS max_ts_step
    FROM
        log_union AS log
    LEFT JOIN
        datalake_atta_clean.proposal AS pp -- tabela com relaçao id_proposal e id_produto
            ON pp.id_proposal = log.id_proposal
    LEFT JOIN
        datalake_atta_clean.track_step_detail AS pre --tabela com status por produto
            ON pre.decision_number = log.id_current_status
            AND pre.id_product = pp.id_product
    WHERE
        pp.id_product IN (1, 11)
    ORDER BY
        log.id_proposal desc,
        log.ts_previous_log,
        log.ts_current_log,
        log.id
  )
  SELECT
    id_proposal,
    id_current_status AS id_status,
    id_previous_proposal_situation AS id_proposal_situation,
    proposal_status,
    proposal_previous_situation AS proposal_situation,
    SUM(leadtime_situation) AS leadtime_situation_in_hour
  FROM log_classified
  GROUP BY 1,2,3,4,5
  ORDER BY 1 DESC,2,3
