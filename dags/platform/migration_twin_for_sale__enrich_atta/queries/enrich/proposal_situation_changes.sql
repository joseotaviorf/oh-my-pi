WITH log_union AS (
    (
        SELECT
            't1' as origin_table,
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
            't2' as origin_table,
            id,
            CAST(id_proposal AS INTEGER) AS id_proposal,
            CAST(GET_JSON_OBJECT(to, '$.Status') AS INTEGER) AS id_current_status,
            CAST(GET_JSON_OBJECT(from, '$.Situacao') AS INTEGER) AS id_previous_proposal_situation,
            CAST(GET_JSON_OBJECT(to, '$.Situacao') AS INTEGER) AS id_current_proposal_situation,
            LAG(ts_created) over(partition by id_proposal order by ts_created) AS ts_previous_log,
            ts_created AS ts_current_log
        FROM
            datalake_atta_clean.log_isolve_v2
        WHERE
            GET_JSON_OBJECT(to, '$.Status') IS NOT NULL
            AND CAST(GET_JSON_OBJECT(from, '$.Situacao') AS INTEGER) IS NOT NULL
            AND type_operation = 'Proposta'
    )
    ),
base AS (
SELECT
        origin_table,
        log.id_proposal,
        pc.id_partner,
        pre.proposal_status,
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
            WHEN 11 THEN 'Não Passível de Defesa'
            WHEN 12 THEN 'Revisão'
            WHEN 13 THEN 'Não Processado Banco'
            WHEN 14 THEN 'Divergência de Cadastro'
            WHEN 15 THEN 'Notas de Exigência'
            WHEN 16 THEN 'Cartório Externo'
            WHEN 17 THEN 'Aprovado Condicionado'
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
            WHEN 11 THEN 'Não Passível de Defesa'
            WHEN 12 THEN 'Revisão'
            WHEN 13 THEN 'Não Processado Banco'
            WHEN 14 THEN 'Divergência de Cadastro'
            WHEN 15 THEN 'Notas de Exigência'
            WHEN 16 THEN 'Cartório Externo'
            WHEN 17 THEN 'Aprovado Condicionado'
        END AS proposal_next_situation,
        pp.ts_registration AS ts_proposal_registration,
        log.ts_previous_log AS ts_start_situation,
        log.ts_current_log AS ts_end_situation,
        -- datediff(hour,COALESCE(log.ts_previous_log,pp.ts_registration),log.ts_current_log) AS leadtime_situation_in_hour,
        MIN(log.ts_current_log) OVER (PARTITION BY log.id_proposal, pre.proposal_status ORDER BY log.id_proposal, pre.proposal_status) AS min_ts_step,
        MAX(log.ts_current_log) OVER (PARTITION BY log.id_proposal, pre.proposal_status ORDER BY log.id_proposal, pre.proposal_status) AS max_ts_step,
        row_number() OVER(PARTITION BY log.id_proposal ORDER BY log.ts_current_log) AS proposal_order
    FROM
        log_union AS log
    LEFT JOIN
        datalake_atta_clean.proposal AS pp -- tabela com relaçao id_proposal e id_produto
            ON pp.id_proposal = log.id_proposal
    LEFT JOIN
        datalake_atta_clean.track_step_detail AS pre --tabela com status por produto
            ON pre.decision_number = log.id_current_status
            AND pre.id_product = pp.id_product
    LEFT JOIN
        datalake_atta_clean.partner_info AS pc -- tabela com infos dos parceiros (5a,CM)
            ON pp.id_partner = pc.id_partner


),
last_situation AS (
  SELECT distinct
    id_proposal,
    CASE WHEN proposal_order = MAX(proposal_order) OVER(PARTITION BY base.id_proposal) THEN proposal_next_situation END AS last_situation
  FROM base
)
,aux AS (
SELECT distinct
  base.id_proposal,
  base.id_partner,
  proposal_order,
  base.proposal_status,
  proposal_previous_situation AS situation_history,
  proposal_next_situation AS next_situation,
  ls.last_situation,
  CASE WHEN proposal_order = LAST_VALUE(proposal_order) OVER(PARTITION BY base.id_proposal) THEN TRUE ELSE FALSE END AS is_last_situation,
  LAST_VALUE(proposal_order) OVER(PARTITION BY base.id_proposal) AS max_order,
  ts_proposal_registration,
  CASE
    WHEN proposal_order = 1 THEN COALESCE(ts_start_situation,ts_proposal_registration)
    WHEN proposal_order > 1 THEN lag(ts_end_situation) OVER(PARTITION BY base.id_proposal ORDER BY proposal_order)
  END AS ts_start_situation,
  ts_end_situation,
  min_ts_step,
  max_ts_step
--   leadtime_situation_in_hour
FROM base
LEFT JOIN
    last_situation ls
        ON base.id_proposal = ls.id_proposal
        AND last_situation IS NOT NULL
),
not_last_situation AS (
SELECT
  id_proposal,
  id_partner,
  proposal_order,
  proposal_status,
  situation_history,
  next_situation,
  DATEDIFF(MINUTE,ts_start_situation,ts_end_situation) AS lead_time_situation_in_minutes,
  DATEDIFF(HOUR,ts_start_situation,ts_end_situation) AS lead_time_situation_in_hour,
  DATEDIFF(DAY,ts_start_situation,ts_end_situation) AS lead_time_situation_in_day,
  DATEDIFF(DAY, date_trunc('day', min_ts_step),COALESCE(date_trunc('day',  max_ts_step),current_date)) AS lead_time_status_in_day,
  ts_proposal_registration,
  ts_start_situation,
  ts_end_situation
FROM aux
),
adj_last_situation AS ( -- criando linha para última situação da proposta
SELECT
  id_proposal,
  id_partner,
  (max_order + 1) AS proposal_order,
  proposal_status,
  last_situation as situation_history,
  NULL AS next_situation,
  DATEDIFF(MINUTE,ts_end_situation,current_date) AS lead_time_situation_in_minutes,
  DATEDIFF(HOUR,ts_end_situation,current_date) AS lead_time_situation_in_hour,
  DATEDIFF(DAY,ts_end_situation,current_date) AS lead_time_situation_in_day,
  DATEDIFF(DAY, date_trunc('day', min_ts_step),COALESCE(date_trunc('day',  max_ts_step),current_date)) AS lead_time_status_in_day,
  ts_proposal_registration,
  ts_end_situation AS ts_start_situation,
  NULL AS ts_end_situation
FROM aux
WHERE is_last_situation = TRUE
),
union_all (
SELECT * FROM not_last_situation
UNION ALL
SELECT * FROM adj_last_situation
)
SELECT
*
FROM union_all
