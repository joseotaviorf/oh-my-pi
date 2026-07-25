WITH target_departments /* 0. Pré-filtro de Departamentos */ AS (
  SELECT
    sk_department,
    department
  FROM dw_customer_support.dim_department
  WHERE
    department IN (
      'CX Pagamentos Ativo [POS] [BACK] [PAY]',
      'CX Alteração de dados bancários [BACK] [POS] [PAY] [WH]',
      'CX Onboarding [BACK] [POS] [WH]',
      'Aditivos [POS] [BACK] [WH]',
      'CX Propostas Tarefas [PRE] [BACK]',
      'Atendimento Escalado [OFF] [POS] [BACK]',
      'Rescisão por Inadimplência [OFF][POS][BACK]',
      'Offboarding Reparos [OFF] [POS] [BACK]',
      'Aditivos [REP] [POS] [BACK]',
      'Alteração de dados bancários [BACK]',
      'FullService [BACK]',
      'Entrada no imóvel [ONB] [POS] [BACK]',
      'Reparos PP Multi [BACK]',
      'Reembolso de Reparos [Back]',
      'Atendimento [Porto]',
      'Triagem [Porto]',
      'CX Atendimento Escalado Receptivo [OFF] [POS] [BACK]'
   )
), pp_multi AS (
  SELECT
    dt_houses_owned AS dt_reference,
    id_owner AS sk_owner,
    ongoing_houses,
    is_pp_multi_active,
    CASE WHEN is_pp_multi_active = TRUE OR ongoing_houses >= 5 THEN TRUE ELSE FALSE END AS is_pp_multi
  FROM datalake_pro_owners.daily_owner_houses_quantity_history
  WHERE
    (
      ongoing_houses >= 5 OR is_pp_multi_active = TRUE
    )
), universo_tickets /* 1. UNIVERSO MESTRE */ AS (
  SELECT
    TRY_CAST(bmt.sk_task AS BIGINT) AS sk_task,
    bmt.ts_started,
    ft.sk_user,
    bmt.sk_agent,
    ft.sk_last_analyst,
    dd.department,
    ppm.is_pp_multi AS is_pp_multi,
    CASE
      WHEN dd.department IN (
         'CX Pagamentos Ativo [POS] [BACK] [PAY]',
      'CX Alteração de dados bancários [BACK] [POS] [PAY] [WH]',
      'CX Onboarding [BACK] [POS] [WH]',
      'Aditivos [POS] [BACK] [WH]',
      'CX Propostas Tarefas [PRE] [BACK]',
      'Atendimento Escalado [OFF] [POS] [BACK]',
      'Rescisão por Inadimplência [OFF][POS][BACK]',
      'Offboarding Reparos [OFF] [POS] [BACK]',
      'Aditivos [REP] [POS] [BACK]',
      'Alteração de dados bancários [BACK]',
      'FullService [BACK]',
      'Entrada no imóvel [ONB] [POS] [BACK]',
      'Reparos PP Multi [BACK]',
      'Reembolso de Reparos [Back]',
      'Atendimento [Porto]',
      'Triagem [Porto]',
      'CX Atendimento Escalado Receptivo [OFF] [POS] [BACK]'
      )
      THEN dt.theme_detail
      ELSE NULL
    END AS theme_detail, /* Tema detalhado apenas para os departamentos específicos */
    CASE
      WHEN dd.department IN (
   'CX Pagamentos Ativo [POS] [BACK] [PAY]',
      'CX Alteração de dados bancários [BACK] [POS] [PAY] [WH]',
      'CX Onboarding [BACK] [POS] [WH]',
      'Aditivos [POS] [BACK] [WH]',
      'CX Propostas Tarefas [PRE] [BACK]',
      'Atendimento Escalado [OFF] [POS] [BACK]',
      'Rescisão por Inadimplência [OFF][POS][BACK]',
      'Offboarding Reparos [OFF] [POS] [BACK]',
      'Aditivos [REP] [POS] [BACK]',
      'Alteração de dados bancários [BACK]',
      'FullService [BACK]',
      'Entrada no imóvel [ONB] [POS] [BACK]',
      'Reparos PP Multi [BACK]',
      'Reembolso de Reparos [Back]',
      'Atendimento [Porto]',
      'Triagem [Porto]',
      'CX Atendimento Escalado Receptivo [OFF] [POS] [BACK]'
      )
      THEN CASE
        WHEN dt.theme_detail IN (
          'doubt_info_responsibility_condo_payment',
          'request_change_responsibility_condo_payment',
          'report_condo_value_different_announced',
          'delete_fix_condo_expenses',
          'add_condo_expenses',
          'report_condo_paid_mistake',
          'report_condo_default',
          'confirm_condo_payment',
          'send_condo_payment_receipt',
          'report_informal_condo',
          'request_refund_infraction_fine',
          'report_expenses_prior_contract',
          'doubt_info_guaranteed_condo',
          'activate_guaranteed_condo',
          'deactivate_guaranteed_condo'
        )
        THEN 'Condomínio'
        WHEN dt.theme_detail IN (
          'doubt_info_iptu_trash_fee',
          'request_iptu_adjustment_value',
          'request_refund_iptu_payment',
          'report_discrepancy_contest_iptu_values',
          'request_iptu_split'
        )
        THEN 'IPTU'
        WHEN dt.theme_detail IN (
          'doubt_info_due_date_boleto',
          'report_discount_agreement_not_applied_wrong_boleto_tenant',
          'request_negotiation_exemption_fine_interest_overdue_rent',
          'request_negotiation_rent_boleto_not_overdue',
          'doubt_info_boleto_values_tenant',
          'request_resend_boleto_tenant',
          'inform_boleto_payment_promise',
          'request_refund_duplicate_rent_payment',
          'report_issues_pay_boleto',
          'report_issues_boleto_payment_credit_card',
          'report_error_recurring_payment_credit_card',
          'request_pause_wrong_charges',
          'doubt_info_rent_adjustment',
          'negotiate_rent_value',
          'negotiate_rent_value_contract_anniversary',
          'negotiate_change_adjustment_index',
          'negotiate_temporary_rent_discount',
          'report_extrajudicial_notice_rent_value',
          'request_invoice_client_active_contract',
          'request_invoice_fix_cancel',
          'report_issues_one_rent_anticipation',
          'report_issues_three_rent_anticipation_new_contracts',
          'report_issues_six_rent_anticipation',
          'report_issues_rent_anticipation_property_vacancy',
          'doubt_info_brokerage_fee_installments',
          'request_cancel_brokerage_fee_installments',
          'request_exemption_brokerage_fee_active_contract',
          'doubt_info_service_fee',
          'doubt_info_administration_fee',
          'doubt_info_owner_invoice_deadlines_values',
          'contest_rent_transfer_values',
          'request_bank_data_change_reversal_transfer',
          'report_discount_agreement_not_applied_wrong_owner_transfer',
          'request_send_statement_receipt_rent_transfer',
          'request_resend_owner_invoice',
          'report_extrajudicial_notice_owner_transfer'
        )
        THEN 'Aluguel'
        WHEN dt.theme_detail IN (
          'delete_fix_condo_expenses',
          'add_condo_expenses'
        )
        THEN 'Reembolso de condomínio'
        WHEN dt.theme_detail IN (
          'request_report_income_tax',
          'request_payment_statement_iq',
          'report_income_report_error',
          'request_income_split',
          'request_final_country_exit_statement_pp_non_resident',
          'request_carne_leao_income_statement'
        )
        THEN 'IR'
        WHEN dt.theme_detail IN (
          'report_inappropriate_behavior_tenants_residents',
          'report_commercial_use_property',
          'report_pets_staying_property',
          'general_subjects_contracts_without_management',
          'doubt_info_simple_bond',
          'transfer_correct_journey_ongoing',
          'request_repairs_ongoing',
          'doubt_guidance_improvements',
          'info_requested_repairs',
          'reimbursement_completed_repair',
          'disagree_repair_responsibility',
          'repairs_responsibility_info',
          'transfer_correct_journey_repairs'
        )
        THEN 'Ongoing'
        ELSE NULL
      END
      ELSE NULL
    END AS subdepartment, /* Lógica de Subdepartamento (Encadeamento) */
    NULLIF(ft.sk_contract, -1) AS sk_contract_ticket,
    CASE
      WHEN bmt.dt_metric_reference >= CURRENT_DATE - INTERVAL '1' DAY
      THEN bmt.status
      ELSE 'solved'
    END AS status_real,
    CASE
      WHEN bmt.dt_metric_reference >= CURRENT_DATE - INTERVAL '1' DAY
      THEN 'BACKLOG_ATIVO'
      ELSE 'RECEM_RESOLVIDO'
    END AS categoria_origem
  FROM dw_customer_support.fact_backlog_metrics_tasks AS bmt
  INNER JOIN target_departments AS dd
    ON bmt.sk_main_department = dd.sk_department
  LEFT JOIN dw_customer_support.fact_tickets AS ft
    ON TRY_CAST(bmt.sk_task AS BIGINT) = ft.sk_ticket
  LEFT JOIN dw_customer_support.dim_ticket AS dit
    ON CAST(dit.sk_ticket AS STRING) = bmt.sk_task
  LEFT JOIN dw_customer_support.dim_taxonomy AS dt
    ON dt.sk_taxonomy = ft.sk_taxonomy
  LEFT JOIN pp_multi AS ppm
    ON ppm.sk_owner = ft.sk_user AND TO_DATE(ppm.dt_reference) = TO_DATE(bmt.ts_started)
  WHERE
    bmt.origin = 'email'
    AND (
      bmt.status IS NULL OR bmt.status IN ('open', 'new', 'hold', 'pending')
    )
    AND (
      (
        bmt.dt_metric_reference = CURRENT_DATE - INTERVAL '1' DAY
      )
      OR (
        bmt.dt_metric_reference = CURRENT_DATE - INTERVAL '3' DAY
        AND ft.ts_solved >= CURRENT_DATE - INTERVAL '3' DAY
      )
    )
    AND NOT dit.tags LIKE '%closed_by_merge%'
), backlog_text_extract /* 2. EXTRAÇÃO DE TEXTO (Spark Regex usa escape duplo \\) */ AS (
  SELECT
    dit.sk_ticket AS sk_task,
    TRY_CAST(REGEXP_EXTRACT(dit.custom_fields, '"ID do ticket vinculado":"(\\d+)"') AS BIGINT) AS id_ticket_vinculado,
    TRY_CAST(REGEXP_EXTRACT(dit.custom_fields, 'Código do Imóvel.*?:.*?(\\d+)') AS BIGINT) AS id_house_texto
  FROM dw_customer_support.dim_ticket AS dit
  INNER JOIN (
    SELECT
      sk_task
    FROM universo_tickets
  ) AS u
    ON dit.sk_ticket = u.sk_task
), flag_regra_1_5 /* 3. REGRAS DE CARTEIRIZAÇÃO */ AS (
  SELECT
    t.sk_ticket,
    t.sk_contract
  FROM dw_customer_support.fact_tickets AS t
  INNER JOIN (
    SELECT DISTINCT
      id_ticket_vinculado
    FROM backlog_text_extract
    WHERE
      NOT id_ticket_vinculado IS NULL
  ) AS bte
    ON t.sk_ticket = bte.id_ticket_vinculado
  WHERE
    t.sk_contract > 0
), flag_regra_2 AS (
  SELECT
    fhl.sk_owner,
    MIN(fhl.sk_contract) AS sk_contract
  FROM dw_rent.fact_house_listings AS fhl
  INNER JOIN (
    SELECT DISTINCT
      sk_user
    FROM universo_tickets
    WHERE
      sk_user > 0
  ) AS u
    ON fhl.sk_owner = u.sk_user
  WHERE
    fhl.sk_contract > 0
  GROUP BY
    1
), flag_regra_2_5 AS (
  SELECT
    bte.sk_task,
    MIN(fhl.sk_contract) AS sk_contract
  FROM backlog_text_extract AS bte
  INNER JOIN dw_rent.fact_house_listings AS fhl
    ON CAST(fhl.sk_house_listing / 1000 AS BIGINT) = bte.id_house_texto
  WHERE
    fhl.sk_contract > 0
  GROUP BY
    1
), flag_regra_3 AS (
  SELECT
    fcp.sk_user,
    fcp.sk_contract
  FROM dw_rent.fact_contract_people AS fcp
  INNER JOIN dw_rent.dim_contract AS dc
    ON fcp.sk_contract = dc.sk_contract
  INNER JOIN (
    SELECT DISTINCT
      sk_user
    FROM universo_tickets
    WHERE
      sk_user > 0
  ) AS u
    ON fcp.sk_user = u.sk_user
  WHERE
    dc.status IN ('Ativo', 'Finalizado')
), tabela_base /* 4. CONSOLIDAÇÃO */ AS (
  SELECT
    u.*,
    COALESCE(u.sk_contract_ticket, r15.sk_contract, r2.sk_contract, r25.sk_contract) AS contrato_prioritario,
    CASE
      WHEN NOT u.sk_contract_ticket IS NULL
      THEN '1. Regra 1: Contrato do Ticket'
      WHEN NOT r15.sk_contract IS NULL
      THEN '1.5. Regra 1.5: Ticket Vinculado'
      WHEN NOT r2.sk_contract IS NULL
      THEN '2. Regra 2: Owner (Vínculo Direto)'
      WHEN NOT r25.sk_contract IS NULL
      THEN '2.5. Regra 2.5: Fallback Texto'
      ELSE NULL
    END AS regra_prioritaria
  FROM universo_tickets AS u
  LEFT JOIN backlog_text_extract AS bte
    ON u.sk_task = bte.sk_task
  LEFT JOIN flag_regra_1_5 AS r15
    ON bte.id_ticket_vinculado = r15.sk_ticket
  LEFT JOIN flag_regra_2 AS r2
    ON u.sk_user = r2.sk_owner
  LEFT JOIN flag_regra_2_5 AS r25
    ON u.sk_task = r25.sk_task
)
/* 5. RELATÓRIO FINAL */
SELECT
  da_last.email AS analyst_email,
  CASE WHEN tb.categoria_origem = 'RECEM_RESOLVIDO' THEN 'INACTIVE' ELSE 'ACTIVE' END AS status,
  tb.sk_task AS sk_task,
  tb.sk_user AS sk_user,
  CASE
    WHEN (
      tb.department LIKE '%Alteração de dados bancários%'
      OR tb.department LIKE '%Pagamentos Ativo%'
    )
    AND tb.is_pp_multi = TRUE
    THEN 'cx_back_pay_pp_multi'
    WHEN (
      tb.department LIKE '%Alteração de dados bancários%'
      OR tb.department LIKE '%Pagamentos Ativo%'
    )
    AND tb.subdepartment = 'Condomínio'
    THEN 'cx_back_pay_cond_geral'
    WHEN (
      tb.department LIKE '%Alteração de dados bancários%'
      OR tb.department LIKE '%Pagamentos Ativo%'
    )
    AND tb.subdepartment = 'IPTU'
    THEN 'cx_back_pay_iptu'
    WHEN (
      tb.department LIKE '%Alteração de dados bancários%'
      OR tb.department LIKE '%Pagamentos Ativo%'
    )
    AND tb.subdepartment = 'Aluguel'
    THEN 'cx_backoffice_payments_aluguel'
    WHEN (
      tb.department LIKE '%Alteração de dados bancários%'
      OR tb.department LIKE '%Pagamentos Ativo%'
    )
    AND tb.subdepartment = 'Reembolso de condomínio'
    THEN 'cx_back_pay_cond_reembolso'
    WHEN tb.department LIKE '%Aditivos%'
    AND tb.is_pp_multi = TRUE
    THEN 'cx_back_aditivos_pp_multi'
    WHEN tb.department LIKE '%Aditivos%'
    AND tb.subdepartment = 'IR'
    THEN 'cx_back_aditivos_ir'
    WHEN tb.department LIKE '%Aditivos%'
    AND tb.subdepartment = 'Ongoing'
    THEN 'cx_back_aditivos_pos'
    WHEN tb.department LIKE '%Onboarding%'
    THEN 'cx_back_onboarding_pos'
    WHEN tb.department LIKE '%Atendimento Escalado%'
    THEN 'cx_offboarding_escalado'
    WHEN tb.department LIKE '%Offboarding Reparos%'
    THEN 'cx_offboarding_mediacao'
    WHEN tb.department LIKE '%Rescisão por Inadimplência%'
    THEN 'cx_offboarding_despejo'
    WHEN tb.department LIKE '%Propostas Tarefas%'
    THEN 'cx_back_visitas_propostas_pre'
    WHEN tb.department LIKE '%Entrada no imóvel%'
    THEN 'cx_back_onboarding_pos'
    WHEN tb.department LIKE '%Reparação Comum%'
    THEN 'reparos_comum'
    WHEN tb.department LIKE '%Reparação (Piloto Urgente)%'
    THEN 'reparos_piloto_urgente'
    WHEN tb.department LIKE '%Reparação Emergencial%'
    THEN 'reparos_emergencial'
    WHEN tb.department LIKE '%FullService [BACK]%'
    THEN 'reparos_contestacao'
    WHEN tb.department LIKE '%Reembolso de Reparos%'
    THEN 'reparos_reembolso'
    WHEN tb.department LIKE '%Reparos PP Multi%'
    THEN 'reparos_pp_multi'
    WHEN tb.department LIKE '%Triagem [Porto]%'
    THEN 'reparos_porto'
    WHEN tb.department LIKE '%Atendimento [Porto]%'
    THEN 'reparos_porto'
    WHEN tb.department LIKE '% CX Atendimento Escalado Receptivo [OFF] [POS] [BACK]%'
     THEN 'cx_offboarding_escalado'

    ELSE 'NÃO IDENTIFICADO'
  END AS context_identifier,
  COALESCE(tb.contrato_prioritario, r3.sk_contract) AS origin_identifier,
  CASE
    WHEN fcp.contract_role = 'landlord'
    THEN 'OWNER'
    WHEN fcp.contract_role = 'tenant'
    THEN 'TENANT'
    WHEN NOT COALESCE(tb.contrato_prioritario, r3.sk_contract) IS NULL
    THEN 'OTHER'
    ELSE NULL
  END AS user_type,
  CASE
    WHEN tb.categoria_origem = 'RECEM_RESOLVIDO'
    THEN 'fechado + 3 dias'
    WHEN tb.status_real IN ('new', 'open')
    THEN 'aberto'
    WHEN tb.status_real = 'hold'
    THEN 'em espera'
    WHEN tb.status_real = 'pending'
    THEN 'pendente'
    WHEN tb.status_real = 'solved'
    THEN 'fechado'
    ELSE tb.status_real
  END AS ticket_status,
  tb.department AS department,
  CASE
    WHEN LOWER(da_last.agent_organization) IN ('atn', 'atento')
    THEN 'atento'
    WHEN LOWER(da_last.agent_organization) IN ('webhelp', 'webhelpbr', 'contractors')
    THEN 'webhelp'
    WHEN LOWER(da_last.agent_organization) IN ('quintoandar.com', 'quintoandar')
    THEN 'quintoandar'
    WHEN da_last.agent_organization IS NULL
    THEN 'Ticket ainda não atribuído'
    ELSE da_last.agent_organization
  END AS agent_organization,
  COALESCE(
    tb.regra_prioritaria,
    CASE
      WHEN NOT r3.sk_contract IS NULL
      THEN '3. Regra 3: Multi-Contrato'
      ELSE '4. Sem Contrato Identificado'
    END
  ) AS contract_identification_rule,
  TO_DATE(tb.ts_started) AS ts_started,
  MIN(tb.ts_started) OVER (PARTITION BY tb.sk_user, tb.department) AS min_ts_started,
  CASE
    WHEN tb.ts_started = MIN(tb.ts_started) OVER (PARTITION BY tb.sk_user, tb.department, COALESCE(tb.contrato_prioritario, r3.sk_contract))
    THEN 'Encaiteirar'
    ELSE 'Duplicado'
  END AS flag,
  COUNT(*) OVER (PARTITION BY tb.sk_user, tb.department) AS tickets_user,
  tb.theme_detail,
  YEAR(TO_DATE(CURRENT_DATE)) AS year,
  MONTH(TO_DATE(CURRENT_DATE)) AS month,
  DAY(TO_DATE(CURRENT_DATE)) AS day,
  NOW() AS ts_load
FROM tabela_base AS tb
LEFT JOIN flag_regra_3 AS r3
  ON tb.sk_user = r3.sk_user AND tb.contrato_prioritario IS NULL
LEFT JOIN dw_customer_support.dim_analyst AS da_last
  ON da_last.sk_analyst = tb.sk_last_analyst
LEFT JOIN dw_rent.fact_contract_people AS fcp
  ON COALESCE(tb.contrato_prioritario, r3.sk_contract) = fcp.sk_contract
  AND tb.sk_user = fcp.sk_user
  AND fcp.is_user = TRUE
