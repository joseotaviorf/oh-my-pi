WITH sessions_filtered AS (
  SELECT 
    id_sauron_session, 
    ts_created, 
    bot
  FROM datalake_chatbot.sessions
  WHERE CAST(ts_created AS DATE) >= DATE('2025-01-01')
),
segments AS (
  SELECT
    fcc.sk_ticket,
    MIN(fcc.ts_task_created - INTERVAL 3 HOURS) as ts_task_created,
    SUM(fcc.total_talk_time) as total_talk_time,
    COUNT(DISTINCT fcc.sk_interaction) as number_of_interaction,
    MAX(s.bot) as bot
  FROM
    dw_customer_support.fact_customer_contacts fcc
  LEFT JOIN 
    sessions_filtered s
      ON CAST(fcc.sk_session AS STRING) = CAST(s.id_sauron_session AS STRING)
  WHERE CAST(fcc.ts_task_created AS DATE) >= DATE('2025-01-01') 
  GROUP BY 1
),

dit_custom_fields AS (
  SELECT
    dit.sk_ticket,
    CAST(GET_JSON_OBJECT(dit.custom_fields, '$["[CC] Causa raíz"]') AS STRING) AS ss_motivo_acionamento,
    CAST(GET_JSON_OBJECT(dit.custom_fields, '$["Nº do PIAE no JIRA "]') AS STRING) AS N_Jira_privacy,
    CAST(GET_JSON_OBJECT(dit.custom_fields, '$["[CC] - Assunto do Contato"]') AS STRING) AS ss_assunto_contato,
    REPLACE(CAST(GET_JSON_OBJECT(dit.custom_fields, '$["Ofensor do Processo"]') AS STRING), '_ofensor_sub', '') AS ss_ofensor_processo,
    REPLACE(CAST(GET_JSON_OBJECT(dit.custom_fields, '$["Área de negócio"]') AS STRING), '_ofensor', '') AS ss_area_negocio,
    CAST(GET_JSON_OBJECT(dit.custom_fields, '$["[CC] - Assunto do Contato"]') AS STRING) AS ss_area_ofensora,
    REPLACE(CAST(GET_JSON_OBJECT(dit.custom_fields, '$["Áreas"]') AS STRING), '_area_5a', '') AS ss_area,
    CAST(GET_JSON_OBJECT(dit.custom_fields, '$["Tarefa aberta corretamente?"]') AS STRING) AS ss_tarefa_aberta_corretamente,
    CAST(GET_JSON_OBJECT(dit.custom_fields, '$["Intermitência Condo"]') AS STRING) AS intermitencia_condo,
    CAST(GET_JSON_OBJECT(dit.custom_fields, '$["Tipo de Cliente"]') AS STRING) AS tipo_de_cliente,
    CAST(GET_JSON_OBJECT(dit.custom_fields, '$["[HUB] Jornada"]') AS STRING) AS jornada_hub,
    CAST(GET_JSON_OBJECT(dit.custom_fields, '$["[CSI] Cliente - Conta Comigo"]') AS STRING) as customer_type_csi,
    -- Ajuste na lógica de extração de data manual do string custom_fields
    CAST(SPLIT_PART(SPLIT_PART(dit.custom_fields, 'Data da viagem ":"', 2), '"', 1) AS DATE) AS dt_viagem_chaves,
    CAST(GET_JSON_OBJECT(dit.custom_fields, '$["Tipo de Demanda"]') AS STRING) AS tipo_de_demanda,
    CAST(GET_JSON_OBJECT(dit.custom_fields, '$["Tipo de processo"]') AS STRING) AS tipo_de_processo,
    CAST(GET_JSON_OBJECT(dit.custom_fields, '$["Has CSAT"]') AS STRING) AS has_csat
  FROM dw_customer_support.dim_ticket dit
  WHERE CAST(ts_created AS DATE) >= DATE('2024-01-01')
),
fact_ticket_csat AS (
  SELECT
    ftc.sk_ticket,
    ftc.last_csat_score,
    ftc.last_csat_comment,
    ftc.ts_last_response,
    ftc.first_csat_score,
    ftc.first_csat_comment,
    ftc.ts_first_response,
    ftc.is_solved
  FROM 
    dw_satisfaction_rating.fact_ticket_csat ftc
  WHERE 
    ftc.ts_first_response >= DATE('2024-01-01')
  QUALIFY
    ROW_NUMBER() OVER (PARTITION BY sk_ticket ORDER BY ts_first_response DESC) = 1
),
tickets_perspective AS (
  SELECT
    ft.sk_ticket,
    ft.sk_user,
    COALESCE(ft.sk_user, ft.sk_contract) AS sk_user_contract,
    ft.ts_last_move_to_final_group,
    ft.sk_contract,
    ft.sk_session,
    ft.channel,
    dit.status,
    ftc.last_csat_score,
    ftc.last_csat_comment,
    ftc.ts_last_response AS last_csat_ts_response,
    ftc.first_csat_score,
    ftc.first_csat_comment,
    ftc.ts_first_response AS first_csat_ts_response,
    ftc.is_solved AS resolution_survey,
    ft.replies,
    ft.reopens,
    ft.front_or_back,
    CASE WHEN ftc.sk_ticket IS NOT NULL THEN TRUE ELSE FALSE END AS has_answered_csat,
    ft.is_ticket_rate,
    ft.ticket_rate_weight,
    ft.ts_created AS ts_started,
    CASE 
      WHEN seg.ts_task_created IS NULL THEN ft.ts_created
      ELSE LEAST(ft.ts_created, seg.ts_task_created) 
    END AS ts_started_new,
    TRUNC(ft.ts_created, 'week') AS ts_started_week,
    ft.ts_closed,
    ft.ts_solved,
    DATEDIFF(ft.ts_solved, ft.ts_created) AS ticket_age,
    dit.tags,
    dit.type AS ticket_type,
    dd_first.department AS first_department,
    dd_first.team AS first_team,
    dd_first.area AS first_area,
    dd_first.is_partner AS first_is_partner,
    dd_last.journey_step,
    dd_last.department AS last_department,
    dd_last.team AS last_team,
    dd_last.area AS last_area,
    dd_last.is_partner AS last_is_partner,
    dt.customer_type_tag AS customer_type,
    dt.motivation,
    dt.step_tag,
    dt.theme,
    dt.theme_detail,
    dt.journey,
    dt.sub_journey,
    dt.line_owner,
    CASE 
      WHEN ft.ticket_origin = 'call inapp' THEN UPPER(ft.direction) 
      WHEN ft.ticket_origin = 'call inbound' THEN 'INBOUND'
      WHEN ft.ticket_origin = 'chat5a' THEN 'INBOUND'
      WHEN ft.ticket_origin = 'call outbound' THEN 'OUTBOUND'
      ELSE UPPER(ft.direction) 
    END AS refined_direction,
    CASE 
      WHEN ft.channel = 'cs email' THEN 'zendesk email'
      ELSE ft.ticket_origin
    END AS refined_ticket_origin,
    da_first.email AS first_agent_email,
    da_first.agent_organization AS first_agent_organization,
    da_first.dt_agent_start AS first_agent_dt_start,
    da_last.email AS last_agent_email,
    da_last.agent_organization AS last_agent_organization,
    da_last.dt_agent_start AS last_agent_dt_start,
    ft.ts_updated, 
    DATEDIFF(CURRENT_DATE(), ft.ts_updated) AS days_since_last_update,
    ft.reply_time_min_business AS minutes_first_reply_time_business,
    ft.reply_time_min_calendar AS minutes_first_reply_time_calendar,
    ft.is_backlog_in_time AS is_ticket_solved_within_sla,
    ft.days_elapsed_business AS days_worked,
    ft.days_elapsed_calendar AS days_worked_with_days_off,
    ft.sla_target,
    TO_TIMESTAMP(ft.ts_latest_customer_comment) - INTERVAL 3 HOURS as ts_latest_customer_comment,
    TO_TIMESTAMP(ft.ts_latest_analyst_comment) - INTERVAL 3 HOURS as ts_latest_analyst_comment,
    calendar.is_brz_business_day,
    -- Canal de Entrada Logic
    CASE 
      WHEN dit.tags LIKE '%tarefa_escalar_atendimento_front%' OR dit.tags LIKE '%magic_link_demanda%' OR dit.tags LIKE '%ticket_ativo%' THEN 'Front'
      WHEN dit.tags LIKE '%form_faq_portabilidade%' OR dit.tags LIKE '%form_faq%' THEN 'Faq'
      ELSE (
        CASE 
          WHEN dit.ticket_via = 'api' THEN 'Api / PWA'
          WHEN dit.ticket_via = 'web' THEN 'Web (quin.to/mensagem)'
          WHEN dit.ticket_via = 'email' THEN 'E-mail'
          ELSE dit.ticket_via
        END
      )
    END AS canal_de_entrada,
    dit.description,
    CASE 
      WHEN dit.tags LIKE '%cas_pesquisa_enviada%' OR dit.tags LIKE '%csi_pesquisa_enviada%' OR dit.score IN ('offered') OR cf.has_csat = 'true' THEN 1
      ELSE 0
    END AS cas_pesquisa_enviada,
    dit.subject,
    CASE 
      WHEN customer_type_csi = 'vendedor_cliente_conta_comigo' THEN 'vendedor'
      WHEN customer_type_csi = 'proprietário_cliente_conta_comigo' THEN 'proprietário'
      WHEN customer_type_csi = 'colaborador_cliente_conta_comigo' THEN 'colaborador'
      WHEN customer_type_csi = 'inquilino_cliente_conta_comigo' THEN 'inquilino'
      WHEN customer_type_csi = 'comprador_cliente_conta_comigo' THEN 'comprador'
      ELSE NULL
    END AS customer_type_csi_mapped,
    dro.client_type as customer_type_ro,
    dro.group_name as group_name_ro,
    dro.contract_journey as journey_ro,
    MONTHS_BETWEEN(ft.ts_created, da_last.dt_agent_start) as last_agent_aging,
    seg.total_talk_time,
    seg.ts_task_created,
    seg.bot,
    ft.sk_main_department,
    CASE WHEN dro.criticality IN ('Emergencial', 'Urgente', 'Comum') THEN dro.criticality ELSE 'Criticidade - Outros' END as criticidade_ro,
    CASE 
      WHEN dro.criticality = 'Emergencial' THEN ft.ts_created + INTERVAL 3 DAYS
      WHEN dro.criticality = 'Urgente' THEN ft.ts_created + INTERVAL 19 DAYS
      WHEN dro.criticality = 'Comum' THEN ft.ts_created + INTERVAL 21 DAYS 
      ELSE ft.ts_created + INTERVAL 21 DAYS
    END AS deadline_ticket_reparos, 
    cf.dt_viagem_chaves,
    cf.ss_motivo_acionamento,
    cf.N_Jira_privacy,
    cf.ss_assunto_contato,
    cf.ss_ofensor_processo,
    cf.ss_area_negocio,
    cf.ss_area,
    cf.ss_tarefa_aberta_corretamente,
    cf.intermitencia_condo,
    cf.tipo_de_cliente,
    cf.jornada_hub,
    cf.tipo_de_demanda,
    cf.tipo_de_processo,
    CASE 
      WHEN cf.ss_tarefa_aberta_corretamente = 'não__aberta_erroneamente' THEN 'Não'
      WHEN cf.ss_tarefa_aberta_corretamente = 'sim__aberta_corretamente' THEN 'Sim'
    END AS tarefa_partners
  FROM dw_customer_support.fact_tickets AS ft
  LEFT JOIN fact_ticket_csat AS ftc 
    ON ftc.sk_ticket = ft.sk_ticket
  LEFT JOIN dw_customer_support.dim_department AS dd_last 
    ON dd_last.sk_department = ft.sk_main_department
  LEFT JOIN dw_customer_support.dim_department AS dd_first 
    ON dd_first.sk_department = ft.sk_first_department
  LEFT JOIN dw_customer_support.dim_taxonomy AS dt 
    ON dt.sk_taxonomy = ft.sk_taxonomy
  LEFT JOIN dw_customer_support.dim_analyst AS da_first 
    ON da_first.sk_analyst = ft.sk_first_analyst
  LEFT JOIN dw_customer_support.dim_analyst AS da_last 
    ON da_last.sk_analyst = ft.sk_last_analyst
  LEFT JOIN dw_customer_support.dim_ticket AS dit 
    ON dit.sk_ticket = ft.sk_ticket
  LEFT JOIN dw_public.dim_date AS calendar 
    ON CAST(calendar.date AS DATE) = CAST(ft.ts_solved AS DATE)
  LEFT JOIN dw_repairs.dim_ongoing_repairs AS dro 
    ON dro.sk_ticket = ft.sk_ticket
  LEFT JOIN segments AS seg 
    ON seg.sk_ticket = ft.sk_ticket
  LEFT JOIN dit_custom_fields AS cf 
    ON cf.sk_ticket = dit.sk_ticket
  WHERE 
    ft.sk_ticket IS NOT NULL
    AND CAST(ft.ts_created AS DATE) >= DATE('2025-01-01')
),
off_tickets AS (
  SELECT 
    tp.ts_started,
    tp.sk_ticket,
    tp.sk_contract,
    CASE 
      WHEN tp.tags LIKE '%checkout_wkf_budg_appr_by_ll%' AND tp.tags LIKE '%checkout_wkf_budg_appr_by_tt%' THEN 'both_agreed'
      WHEN tp.tags LIKE '%checkout_wkf_budg_appr_by_ll%' THEN 'll_agreed'
      WHEN tp.tags LIKE '%checkout_wkf_budg_appr_by_tt%' THEN 'tt_agreed'
      ELSE 'both_disagreed_no_answer'
    END as status_agreement,
    CASE 
      WHEN tp.tags LIKE '%"pp_multi"%' THEN 'Squad 6 - PP Multi'
      WHEN tp.tags LIKE '%high_value%' THEN 'Squad 5 - High Value'
      WHEN tp.tags LIKE '%checkout_wkf_budg_appr_by_ll%' AND tp.tags LIKE '%checkout_wkf_budg_appr_by_tt%' THEN 'Squad 1 - Ambos Aprovam'
      WHEN tp.tags LIKE '%checkout_wkf_budg_appr_by_ll%' THEN 'Squad 2 - PP Aprova'
      WHEN tp.tags LIKE '%checkout_wkf_budg_appr_by_tt%' THEN 'Squad 3 - IQ Aprova'
      ELSE 'Squad 4 - PP e IQ reprovam ou sem resposta'
    END as squad,
    ts.type as tipo_offboarding,
    CASE 
      WHEN ts.type = 'TERMINATION_LANDLORD' AND tp.last_department in ('Offboarding Reparos [OFF] [POS] [BACK]', 'CX Off Manager [SPOC]') AND cast(ts.id_external as bigint) = tp.sk_ticket THEN 'MED'
      WHEN med.has_mediation_ticket = true THEN 'MED'
      WHEN ts.type = 'TERMINATION_INSPECTION_REVIEW' THEN 'AR'
      WHEN ts.type = 'TERMINATION_CONTESTATION' AND tp.tags NOT LIKE '%early-both-agree%' AND tp.tags NOT LIKE '%early-mediation%' THEN 'AC' 
      ELSE NULL 
    END as off_area
  FROM tickets_perspective tp
  LEFT JOIN datalake_terminator_clean.termination t 
    ON CAST(t.id_contract AS bigint) = tp.sk_contract
  LEFT JOIN datalake_terminator_clean.termination_task ts 
    ON t.id = ts.id_termination AND cast(ts.id_external as bigint) = tp.sk_ticket
  LEFT JOIN datalake_offboarding.mediations as med 
    ON t.id = med.id_termination and tp.sk_ticket = cast(med.id_mediation_ticket as bigint)
  WHERE
    (
      (tp.last_department in ('Offboarding Reparos [OFF] [POS] [BACK]', 'CX Off Manager [SPOC]') AND ts.type = 'TERMINATION_LANDLORD')
      OR med.has_mediation_ticket = true
      OR ts.type in ('TERMINATION_INSPECTION_REVIEW', 'TERMINATION_CONTESTATION')
    )
  QUALIFY
    ROW_NUMBER() OVER (PARTITION BY sk_contract, off_area ORDER BY ts_started DESC) = 1
),
recontact_drilldown_d4 AS (
  SELECT 
    tp.sk_ticket,
    DATE_SUB(CAST(tp.ts_started AS DATE), 3) AS recontact_search_window_from,
    tp.ts_started AS recontact_search_window_until,
    -- Recontact Flag
    IF(DATEDIFF(CAST(tp.ts_started AS DATE), LAG(CAST(tp.ts_started AS DATE)) OVER (PARTITION BY tp.sk_user_contract, tp.last_team ORDER BY tp.ts_started)) <= 3 
       AND tp.ts_started != LAG(tp.ts_started) OVER (PARTITION BY tp.sk_user_contract, tp.last_team ORDER BY tp.ts_started), 1, 0) AS recontact_flag,
    -- Theme Recontact Flag
    IF(tp.theme IS NOT NULL AND DATEDIFF(CAST(tp.ts_started AS DATE), LAG(CAST(tp.ts_started AS DATE)) OVER (PARTITION BY tp.sk_user_contract, tp.last_team, tp.theme ORDER BY tp.ts_started)) <= 3 
       AND tp.ts_started != LAG(tp.ts_started) OVER (PARTITION BY tp.sk_user_contract, tp.last_team ORDER BY tp.ts_started), 1, 0) AS theme_recontact_flag,
    -- FCR Flag (Lead)
    IF(DATEDIFF(LEAD(CAST(tp.ts_started AS DATE)) OVER (PARTITION BY tp.sk_user, tp.last_team ORDER BY tp.ts_started), CAST(tp.ts_started AS DATE)) <= 4
       AND tp.sk_ticket != LEAD(tp.sk_ticket) OVER (PARTITION BY tp.sk_user_contract, tp.last_team ORDER BY tp.ts_started)
       AND tp.ts_started != LEAD(tp.ts_started) OVER (PARTITION BY tp.sk_user_contract, tp.last_team ORDER BY tp.ts_started), 1, 0) AS recontact_fcr_flag,
    LAG(tp.sk_ticket) OVER (PARTITION BY tp.sk_user, tp.last_team, tp.theme ORDER BY tp.ts_started) AS previous_contact_sk_ticket,
    LAG(tp.ts_started) OVER (PARTITION BY tp.sk_user, tp.last_team, tp.theme ORDER BY tp.ts_started) AS previous_contact_ts_started,
    LAG(tp.channel) OVER (PARTITION BY tp.sk_user, tp.last_team, tp.theme ORDER BY tp.ts_started) AS previous_contact_channel,
    LAG(tp.theme) OVER (PARTITION BY tp.sk_user, tp.last_team, tp.theme ORDER BY tp.ts_started) AS previous_contact_theme,
    LAG(tp.first_csat_score) OVER (PARTITION BY tp.sk_user, tp.last_team, tp.theme ORDER BY tp.ts_started) AS previous_contact_csat,
    DATEDIFF(CAST(tp.ts_started AS DATE), LAG(CAST(tp.ts_started AS DATE)) OVER (PARTITION BY tp.sk_user, tp.last_team, tp.theme ORDER BY tp.ts_started)) AS days_since_last_contact
  FROM tickets_perspective AS tp
  WHERE 
    tp.refined_direction = 'INBOUND'
    AND tp.last_department NOT IN ('Welcome Onboarding [BACK] [POS]', 'CX Welcome Onboarding [FRONT][POS]')
    AND tp.channel IN ('call', 'chat')
    AND tp.sk_user IS NOT NULL
    AND tp.sk_user > 0
),
pp_multi AS (
  SELECT   
    id_owner as sk_owner,
    ongoing_houses,
    year, 
    month, 
    day,
    TRUE AS is_pp_multi
  FROM datalake_pp_multi.pp_multi_classification_history ppm
  -- Spark SQL doesn't use LEFT JOIN filter like that often, simplified to logic
  WHERE pp_multi_classification = 'ACTIVE' AND ppm.year >= 2025
),
spoc AS (
  SELECT 
    ft.sk_termination,
    ft.sk_contract,
    ft.ts_termination_request,
    ft.ts_termination_finished,
    ft.ts_termination_canceled,
    ft.is_spoc_contract,
    ft.spoc_wave,
    ft.is_spoc_control_group,
    dit.team as spoc_team,
    CASE 
      WHEN CAST(ts_termination_request AS DATE) < DATE('2025-05-22') AND is_spoc_contract = TRUE AND (is_spoc_control_group = FALSE OR is_spoc_control_group IS NULL) THEN 'before_wave_6_lab_test'
      WHEN CAST(ts_termination_request AS DATE) >= DATE('2025-05-22') AND is_spoc_contract = TRUE AND (is_spoc_control_group = FALSE OR is_spoc_control_group IS NULL) AND (dit.team IN ('ROLLOUT', 'BAU_LONG_LDT', 'BAU_SHORT_LDT') OR dit.team IS NULL) THEN 'rollout'
      ELSE 'other'
    END as spoc_class
  FROM dw_offboarding.fact_terminations as ft
  LEFT JOIN dw_offboarding.dim_termination dit 
    ON ft.sk_termination = dit.sk_termination
  WHERE ft.ts_termination_canceled IS NULL AND CAST(ft.ts_termination_request AS DATE) >= DATE('2025-01-01')
),
vistorias AS (
  SELECT
    fi.sk_contract,
    MAX(IF(di.inspection_type = 'onboarding', CAST(fi.ts_synced - INTERVAL 3 HOURS AS DATE), NULL)) AS onboarding_synced_insp_date,
    MAX(IF(di.inspection_type = 'offboarding', CAST(fi.ts_synced - INTERVAL 3 HOURS AS DATE), NULL)) AS offboarding_synced_insp_date,
    MAX(dt_entrance) as dt_entrance,
    MAX(IF(di.inspection_type = 'offboarding' AND fi.ts_synced IS NOT NULL, fri.is_early_both_agree, NULL)) AS offboarding_early_both_agree
  FROM
    dw_inspections.fact_inspection AS fi
  JOIN dw_inspections.dim_inspection AS di 
    ON di.sk_inspection = fi.sk_inspection
  JOIN dw_rent.dim_contract dc 
    ON fi.sk_contract = dc.sk_contract 
  LEFT JOIN dw_inspections.fact_report_inspections fri 
    ON CAST(fi.sk_inspection AS STRING) = CAST(fri.sk_inspection AS STRING)
  WHERE
    fi.ts_synced IS NOT NULL AND CAST(fi.ts_synced AS DATE) >= DATE('2025-01-01') AND di.status != 'cancelled'
  GROUP BY 1
),
first_resolution AS (
  SELECT 
    last_agent_email, 
    min(ts_solved) as first_resolution 
  FROM tickets_perspective 
  GROUP BY 1 
)
SELECT 
  tp.sk_ticket,
  tp.sk_user,
  tp.sk_user_contract,
  tp.ts_last_move_to_final_group,
  tp.sk_contract,
  tp.sk_session,
  tp.channel,
  tp.status,
  tp.last_csat_score,
  tp.last_csat_comment,
  tp.last_csat_ts_response,
  tp.first_csat_score,
  tp.first_csat_comment,
  tp.first_csat_ts_response,
  tp.resolution_survey,
  tp.replies,
  tp.reopens,
  tp.front_or_back,
  tp.has_answered_csat,
  tp.is_ticket_rate,
  tp.ticket_rate_weight,
  tp.ts_started,
  tp.ts_started_new,
  tp.ts_started_week,
  tp.ts_closed,
  tp.ts_solved,
  tp.ticket_age,
  tp.tags,
  tp.ticket_type,
  tp.first_department,
  tp.first_team,
  tp.first_area,
  tp.first_is_partner,
  tp.journey_step,
  tp.last_department,
  tp.last_team,
  tp.last_area,
  tp.last_is_partner,
  tp.customer_type,
  tp.motivation,
  tp.step_tag,
  tp.theme,
  tp.theme_detail,
  tp.journey,
  tp.sub_journey,
  tp.line_owner,
  tp.refined_direction,
  tp.refined_ticket_origin,
  tp.first_agent_email,
  tp.first_agent_organization,
  tp.first_agent_dt_start,
  tp.last_agent_email,
  tp.last_agent_organization,
  tp.last_agent_dt_start,
  tp.ts_updated, 
  tp.days_since_last_update,
  tp.minutes_first_reply_time_business,
  tp.minutes_first_reply_time_calendar,
  tp.is_ticket_solved_within_sla,
  tp.days_worked,
  tp.days_worked_with_days_off,
  tp.sla_target,
  tp.ts_latest_customer_comment,
  tp.ts_latest_analyst_comment,
  tp.is_brz_business_day,
  tp.canal_de_entrada,
  tp.description,
  tp.cas_pesquisa_enviada,
  tp.subject,
  tp.customer_type_csi_mapped,
  tp.customer_type_ro,
  tp.group_name_ro,
  tp.journey_ro,
  tp.last_agent_aging,
  tp.total_talk_time,
  tp.ts_task_created,
  tp.bot,
  tp.sk_main_department,
  tp.criticidade_ro,
  tp.deadline_ticket_reparos, 
  tp.dt_viagem_chaves,
  tp.ss_motivo_acionamento,
  tp.N_Jira_privacy,
  tp.ss_assunto_contato,
  tp.ss_ofensor_processo,
  tp.ss_area_negocio,
  tp.ss_area,
  tp.ss_tarefa_aberta_corretamente,
  tp.intermitencia_condo,
  tp.tipo_de_cliente,
  tp.jornada_hub,
  tp.tipo_de_demanda,
  tp.tipo_de_processo,
  tp.tarefa_partners,
  rd4.recontact_search_window_from AS recontact_search_window_from_d4,
  rd4.recontact_flag AS recontact_flag_d4,
  ppm.is_pp_multi,
  IF(tp.tags LIKE '%closed_by_merge%', 1, 0) as is_closed_by_merge,
  spoc.spoc_class,
  vt.onboarding_synced_insp_date,
  fr.first_resolution as first_resolution_last_agent,
  CASE 
    WHEN (WEEKDAY(deadline_ticket_reparos) = 6 OR ddend.is_brz_holiday = 'Holiday') 
    THEN deadline_ticket_reparos + INTERVAL 1 DAYS 
    ELSE deadline_ticket_reparos 
  END AS dt_max_end_reparos,
  off.squad,
  off.status_agreement,
  off.off_area,
  YEAR(tp.ts_started) AS year,
  MONTH(tp.ts_started) AS month,
  DAY(tp.ts_started) AS day,
  NOW() AS ts_load
FROM tickets_perspective AS tp
LEFT JOIN recontact_drilldown_d4 AS rd4 
  ON rd4.sk_ticket = tp.sk_ticket
LEFT JOIN pp_multi AS ppm 
  ON ppm.sk_owner = tp.sk_user 
  AND ppm.year = YEAR(tp.ts_started) 
  AND ppm.month = MONTH(tp.ts_started) 
  AND ppm.day = DAY(tp.ts_started)
LEFT JOIN spoc 
  ON tp.sk_contract = spoc.sk_contract
LEFT JOIN first_resolution AS fr 
  ON fr.last_agent_email = tp.last_agent_email
LEFT JOIN vistorias vt 
  ON vt.sk_contract = tp.sk_contract
LEFT JOIN dw_public.dim_date as ddend 
  ON CAST(ddend.date AS DATE) = CAST(deadline_ticket_reparos AS DATE)
LEFT JOIN off_tickets off 
  ON tp.sk_ticket = off.sk_ticket 
WHERE 
  DATE(tp.ts_started) BETWEEN DATE('{load_start_date}') - INTERVAL '6' MONTH AND DATE('{load_end_date}')
