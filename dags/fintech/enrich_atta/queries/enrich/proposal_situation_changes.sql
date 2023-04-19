WITH log_union AS (
    (
        SELECT
            't1' AS origin_table,
            CAST(id AS STRING) AS id,
            id_proposal,
            id_current_status,
            id_previous_proposal_situation,
            id_current_proposal_situation,
            lag(ts_current_log) OVER(PARTITION BY id_proposal,id_current_status ORDER BY ts_current_log) AS ts_previous_log,
            ts_current_log
        FROM
            datalake_atta_clean.log_isolve_v1
    )
    UNION
    (
        SELECT
            't2' AS origin_table,
            id,
            CAST(id_proposal AS INTEGER) AS id_proposal,
            CAST(GET_JSON_OBJECT(TO, '$.Status') AS INTEGER) AS id_current_status,
            CAST(GET_JSON_OBJECT(FROM, '$.Situacao') AS INTEGER) AS id_previous_proposal_situation,
            CAST(GET_JSON_OBJECT(TO, '$.Situacao') AS INTEGER) AS id_current_proposal_situation,
            CAST(GET_JSON_OBJECT(FROM, '$.DtUltAtu') AS TIMESTAMP) AS ts_previous_log,
            to_utc_timestamp(GET_JSON_OBJECT(to, '$.DtUltAtu') , 'UTC+3') AS ts_current_log
        FROM
            datalake_atta_clean.log_isolve_v2
        WHERE
            GET_JSON_OBJECT(TO, '$.Status') IS NOT NULL
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
        END AS proposal_next_situation,
        pp.ts_registration AS ts_proposal_registration,
        log.ts_previous_log AS ts_start_situation,
        log.ts_current_log AS ts_end_situation,
        DATEDIFF(HOUR,COALESCE(log.ts_previous_log,pp.ts_registration),log.ts_current_log) AS lead_time_situation_in_hour,
        DATEDIFF(DAY,COALESCE(log.ts_previous_log,pp.ts_registration),log.ts_current_log) AS lead_time_situation_in_day,
        MIN(log.ts_current_log) OVER (PARTITION BY log.id_proposal, pre.proposal_status ORDER BY log.id_proposal, pre.proposal_status) AS min_ts_step,
        MAX(log.ts_current_log) OVER (PARTITION BY log.id_proposal, pre.proposal_status ORDER BY log.id_proposal, pre.proposal_status) AS max_ts_step,
        ROW_NUMBER() OVER(PARTITION BY log.id_proposal ORDER BY log.ts_previous_log) AS proposal_order
    FROM
        log_union AS log
    LEFT JOIN
        datalake_atta_clean.proposal AS pp -- table with relation id_proposal and id_produto
            ON pp.id_proposal = log.id_proposal
    LEFT JOIN
        datalake_atta_clean.track_step_detail AS pre -- table with product status
            ON pre.decision_number = log.id_current_status
            AND pre.id_product = pp.id_product
    LEFT JOIN
        datalake_atta_clean.partner_info AS pc -- table with partner information (5a,CM)
            ON pp.id_partner = pc.id_partner
    WHERE
        pp.id_product IN (1, 11)
),
last_situation AS (
  SELECT DISTINCT
    id_proposal,
    CASE WHEN proposal_order = MAX(proposal_order) OVER(PARTITION BY base.id_proposal) THEN proposal_next_situation END AS last_situation
  FROM base
),
aux AS (
SELECT DISTINCT
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
  COALESCE(ts_start_situation,ts_proposal_registration) AS ts_start_situation,
  ts_end_situation,
  lead_time_situation_in_hour,
  lead_time_situation_in_day,
  min_ts_step,
  max_ts_step
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
  ts_proposal_registration,
  ts_start_situation,
  ts_end_situation,
  lead_time_situation_in_hour,
  lead_time_situation_in_day,
    DATEDIFF(DAY, date_trunc('day', min_ts_step),date_trunc('day',  max_ts_step)) AS lead_time_status_in_day
FROM aux
),
adj_last_situation AS ( -- add line for last proposal situation
SELECT
  id_proposal,
  id_partner,
  (max_order + 1) AS proposal_order,
  proposal_status,
  last_situation as situation_history,
  NULL AS next_situation,
  ts_proposal_registration,
  ts_end_situation AS ts_start_situation,
  NULL AS ts_end_situation,
  DATEDIFF(HOUR,ts_end_situation,current_date) AS lead_time_situation_in_hour,
  DATEDIFF(DAY,ts_end_situation,current_date) AS lead_time_situation_in_day,
  DATEDIFF(DAY, date_trunc('day', min_ts_step),date_trunc('day',  max_ts_step)) AS lead_time_status_in_day
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
ORDER BY
   id_proposal DESC,
   ts_start_situation,
   ts_end_situation
