WITH last_extracted AS (
    SELECT
        id_group,
        name,
        dt_extracted
    FROM
        datalake_velo_zendesk_clean.groups
    QUALIFY
        ROW_NUMBER() OVER(PARTITION BY id_group ORDER BY dt_extracted DESC) = 1
    ),

last_register AS (
    SELECT
          id_ticket,
          MAX(ts_updated) AS ts_updated,
          MAX(ts_load) AS ts_load
      FROM
          datalake_velo_zendesk_clean.tickets_history
      GROUP BY
          1
    ),

base_survicate AS (
  SELECT
      rc.id_response AS id_answer,
      sr.id_survey,
      sr.id_respondent,
      REGEXP_EXTRACT(sr.response_url, 'contractid=([0-9]+)', 1) AS id_contract,
      REGEXP_EXTRACT(sr.response_url, 'ticket_id=([0-9]+)', 1) AS id_ticket,
      REGEXP_EXTRACT(sr.response_url, 'email=([^&]+)', 1) AS email,
      'survicate' AS survey_source,
      rc3.answer_content AS user_comment,
      rc2.answer_content AS smiley_scale,
      rc.answer_content AS satisfaction_rating,
      'satisfaction evaluation' AS score_description,
      rc.ts_collected AS ts_first_response,
      rc.year,
      rc.month,
      rc.day
  FROM
      datalake_survicate.survey_responses AS sr
  LEFT JOIN
      datalake_survicate.response_content AS rc
          ON sr.id_response = rc.id_response
          AND rc.id_question = '2461800'
  LEFT JOIN
      datalake_survicate.response_content AS rc2
          ON sr.id_response = rc2.id_response
          AND rc2.id_question = '2461801'
  LEFT JOIN
      datalake_survicate.response_content AS rc3
          ON sr.id_response = rc3.id_response
          AND rc3.id_question = '2461802'
  WHERE
      sr.id_survey IN ('7c875afca4130e7a')
)

    SELECT
        th.id_ticket,
        SUBSTRING(REGEXP_EXTRACT(th.description, 'Este é um acompanhamento da sua solicitação anterior #([0-9]+)',0),55,6) as id_main_ticket,
        cf.id_delinquency,
        th.id_assignee,
        th.id_group,
        th.id_requester,
        th.id_submitter,
        CASE
            WHEN th.custom_fields LIKE '%"inadimplência_2_dias_sem_juros_e_multa"%' THEN '2 days'
            WHEN cf.request_type LIKE '%receber_em_2_dias%' THEN '2 days'
            WHEN cf.request_type LIKE '%inadimplência_15_dias_com_juros_e_multa%' THEN '15 days'
            WHEN cf.request_type LIKE '%receber_em_15_dias%' THEN '15 days'
            WHEN cf.request_type LIKE '%cancelamento_de_contrato_com_acionamento_de_garantia%' THEN 'Cancellation'
            WHEN cf.guarantee_activation LIKE '%com_acionamento%' THEN 'Cancellation'
            ELSE NULL
        END AS short_request_type,
        th.description,
        cf.request_error,
        cf.request_type,
        cf.cancellation_reason,
        cf.broker_name,
        cf.contact_reason,
        cf.tenant_name,
        cf.client_request,
        th.recipient,
        CAST(GET_JSON_OBJECT(th.via, '$.channel') AS STRING) AS ticket_via,
        th.type AS ticket_type,
        le.name,
        th.priority,
        COALESCE(s.satisfaction_rating, SPLIT(REPLACE(REPLACE(SPLIT(th.satisfaction_rating, ':')[1],'}}',''),'"',''),',')[0]) AS satisfaction_rating,
        SPLIT(REPLACE(REPLACE(SPLIT(th.satisfaction_rating, ':')[2],'}}',''),'"',''),',')[0] AS satisfaction_reason,
        COALESCE(s.user_comment, SPLIT(REPLACE(REPLACE(SPLIT(th.satisfaction_rating, ':')[3],'}}',''),'"',''),',')[0]) AS satisfaction_comments,
        s.smiley_scale,
        ROW_NUMBER() OVER(PARTITION BY th.id_ticket ORDER BY th.ts_updated DESC) AS ticket_order,
        th.subject,
        th.url_ticket AS ticket_url,
        th.status AS ticket_status,
        th.tags,
        th.has_incidents,
        th.is_public,
        lr.ts_updated = th.ts_updated AS is_last_register,
        CASE
            WHEN cf.has_payment_forwarded = 'não_inad' THEN FALSE
            WHEN cf.has_payment_forwarded = 'sim_inad' THEN TRUE
            ELSE NULL
        END AS has_payment_forwarded,
        th.dt_extracted,
        th.ts_created,
        th.ts_created_local,
        th.ts_updated,
        FROM_UTC_TIMESTAMP(th.ts_updated, 'Brazil/East') AS ts_updated_local,
        th.ts_load
    FROM
        datalake_velo_zendesk_clean.tickets_history th
    LEFT JOIN
        last_extracted le
        ON le.id_group = th.id_group
    LEFT JOIN
        datalake_velo_zendesk.custom_fields cf
        ON th.id_ticket = cf.id_ticket
    LEFT JOIN
        last_register lr
        ON th.id_ticket = lr.id_ticket
        AND th.ts_updated = lr.ts_updated
        AND th.ts_load = lr.ts_load
    LEFT JOIN
        base_survicate s
        ON s.id_ticket = th.id_ticket
