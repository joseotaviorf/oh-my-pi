SELECT DISTINCT
  e.id_ticket,
  e.department AS main_department,
  e.contact_theme_tag AS theme,
  e.contact_theme_detail_tag AS theme_detail,
  e.tags,
  (e.tags LIKE '%escalar_back_midias%' OR e.tags LIKE '%escalar_ouvidoria_hard_cases%') AS has_scale_midia_tag,
  e.tags LIKE '%tarefa_atendimento_escalado%' AS has_scaled_service_task_tag,
  e.tags LIKE '%orçamentação_realizada%' AS has_budgeting_tag,
  e.tags LIKE '%de_r__750_a_r__1.000%' AS has_budget_750_to_1000,
  e.tags LIKE '%de_1.000_a_r__2.500%' AS has_budget_1000_to_2500,
  e.tags LIKE '%%acima_de_2.500%' AS has_budget_above_2500,
  e.custom_fields LIKE '%[WEB]%' AS has_quinto_tag,
  tf.recipient,
  DATE(
    GET_JSON_OBJECT(
      REPLACE(REPLACE(tf.custom_fields, '[', ''), ']', ''),
      '$.Data Orçamentação realizada '
    )
  ) AS dt_budgeting,
  e.ts_ticket_started AS ts_started,
  e.ts_ticket_ended AS ts_ended,
  e.ts_ticket_solved AS ts_solved
FROM
  datalake_customer_support.email e
LEFT JOIN
  datalake_zendesk_ticket_funnels.ticket_funnel tf
    ON e.id_ticket = tf.id_ticket