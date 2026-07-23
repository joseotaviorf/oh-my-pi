WITH payment AS (
  SELECT
    'payment' AS origin_table,
    sk_propose AS id_propose,
    sk_payment AS id,
    id_subscription,
    due_amount AS value,
    dt_created,
    dt_due,
    dt_paid,
    payment_category.desc_lvl_1 AS payment_category,
    status_pay.desc_lvl_1 AS status,
    gateway.desc_lvl_1 AS gateway,
    billing.desc_lvl_1 AS billing_type
  FROM dw_velo.fact_velo_payment AS p
  LEFT JOIN dw_velo.dim_velo_junk AS status_pay
    ON status_pay.sk_junk = p.sk_status
  LEFT JOIN dw_velo.dim_velo_junk AS gateway
    ON gateway.sk_junk = p.sk_payment_gateway
  LEFT JOIN dw_velo.dim_velo_junk AS billing
    ON billing.sk_junk = p.sk_billing_type
  LEFT JOIN dw_velo.dim_velo_junk AS payment_category
    ON p.sk_payment_category = payment_category.sk_junk
), cte_categories_details_merged AS (
  (
    SELECT
      cfc.id_securities,
      cfc.id_group,
      cfc.id_category,
      cfc.category_percentage,
      cfc.category_value
    FROM datalake_velo_omie.cash_flows_categories AS cfc
  )
  UNION ALL
  (
    SELECT
      cf.id_securities,
      cf.id_group,
      cf.id_category,
      100 AS category_percentage,
      cf.due_amount AS category_value
    FROM datalake_velo_omie.cash_flows AS cf
    WHERE
      categories IS NULL
  )
), cte_transactions AS (
  SELECT
    cf.id_securities,
    cte_cat.id_category,
    cf.id_bank_account,
    cf.id_client,
    cf.id_project,
    cf.contract_number,
    p.project_name AS project,
    cf.status,
    cf.id_group AS transaction_type,
    CASE
      WHEN c2.description IN ('Alugueis', 'Condominio')
      THEN 'ongoing'
      WHEN c2.description IN ('Danos ao Imóvel', 'Rescisão')
      THEN 'rescisão'
      ELSE NULL
    END AS transaction_purpose,
    cte_cat.category_percentage AS percent_amount_from_transaction,
    SIGN(cf.due_amount) * cte_cat.category_value AS due_amount,
    cte_cat.category_percentage / 100 * cf.paid_amount AS paid_amount,
    c1.account_tag = 'Garantia Locaticia' AS is_occurency,
    COALESCE(CAST(SPLIT(cf.id_installment, '/')[0] AS DOUBLE), 0) AS installment,
    COALESCE(CAST(SPLIT(cf.id_installment, '/')[1] AS DOUBLE), 0) AS total_installments,
    SUM(
      CASE
        WHEN cf.id_group = 'CONTA_A_RECEBER' AND NOT cf.id_project IS NULL
        THEN cf.securities_value
        ELSE 0
      END
    ) OVER (PARTITION BY cf.id_project, cf.dt_register) > 0
    AND NOT cf.id_project IS NULL AS is_project_receivable_created,
    SUM(
      CASE
        WHEN cf.id_group = 'CONTA_A_RECEBER' AND NOT cf.id_project IS NULL
        THEN cf.securities_value
        ELSE 0
      END
    ) OVER (PARTITION BY cf.id_project, cf.dt_register) >= SUM(
      CASE
        WHEN cf.id_group = 'CONTA_A_PAGAR' AND NOT cf.id_project IS NULL
        THEN cf.securities_value
        ELSE 0
      END
    ) OVER (PARTITION BY cf.id_project, cf.dt_register)
    AND NOT cf.id_project IS NULL AS is_project_receivable_greater_than_payable,
    cf.dt_issue,
    cf.dt_register,
    cf.dt_due,
    cf.dt_payment AS dt_paid,
    cf.ts_created,
    cf.ts_modified
  FROM datalake_velo_omie.cash_flows AS cf
  LEFT JOIN cte_categories_details_merged AS cte_cat
    ON cte_cat.id_securities = cf.id_securities AND cte_cat.id_group = cf.id_group
  LEFT JOIN datalake_velo_omie_clean.projects AS p
    ON cf.id_project = p.id_project
  LEFT JOIN datalake_velo_omie_clean.categories AS c1
    ON c1.id_category = cte_cat.id_category
  LEFT JOIN datalake_velo_omie_clean.categories AS c2
    ON c2.id_category = cf.id_category
  LEFT JOIN datalake_velo_omie_clean.bank_account AS ba
    ON ba.id_account = cf.id_bank_account
  WHERE
    cf.id_group IN ('CONTA_A_PAGAR', 'CONTA_A_RECEBER') AND cf.status <> 'CANCELADO'
), new AS (
  SELECT
    CAST(CONCAT(ct.id_securities, REPLACE(ct.id_category, '.', '')) AS BIGINT) AS id_transaction_entry,
    CAST(CONCAT(
      ct.id_securities,
      CASE WHEN ct.transaction_type = 'CONTA_A_RECEBER' THEN '0' ELSE '1' END
    ) AS BIGINT) AS id_transaction,
    ct.id_category,
    ct.contract_number AS id_propose,
    ct.id_bank_account,
    ct.id_client AS id_omie_client,
    ct.project,
    ct.status,
    ct.transaction_type,
    ct.transaction_purpose,
    ct.installment,
    ct.total_installments AS total_expected_installments,
    ct.percent_amount_from_transaction,
    ct.due_amount,
    ct.paid_amount,
    ct.is_occurency,
    ct.is_project_receivable_created,
    ct.is_project_receivable_greater_than_payable,
    ct.dt_issue,
    ct.dt_register,
    ct.dt_due,
    ct.dt_paid,
    ct.ts_created,
    ct.ts_modified
  FROM cte_transactions AS ct
), ajuste_omie AS (
  SELECT
    new.id_propose AS id_propose_new,
    old.id_propose AS id_propose_old,
    old.*
  FROM datalake_velo.transaction_entries AS old
  FULL OUTER JOIN new
    ON new.id_transaction_entry = old.id_transaction_entry
  WHERE
    new.id_propose <> old.id_propose
), base_omie AS (
  SELECT
    te.sk_transaction_entry,
    t.sk_transaction,
    te.sk_propose,
    COALESCE(ajuste_omie.id_propose_new, te.sk_propose) AS sk_propose_20,
    te.percent_amount_from_transaction,
    te.due_amount,
    (
      te.paid_amount - cf.discount_value
    ) AS paid_amount,
    (
      te.due_amount - cf.discount_value
    ) - (
      te.paid_amount - cf.discount_value
    ) AS open_amount,
    cf.discount_value,
    te.dt_register,
    te.dt_due,
    te.dt_paid,
    te.sk_omie_client,
    oc.corporate_name,
    oc.name_doing_business_as,
    oc.client_cpf_cnpj,
    oc.corporate_name || ' ' || oc.client_cpf_cnpj AS chave_assinatura,
    COALESCE(t.project, (
      oc.corporate_name || ' ' || oc.client_cpf_cnpj
    )) AS chave,
    t.project,
    t.transaction_type,
    c.description,
    CASE
      WHEN te.sk_category = '1.01.03'
      THEN 'Taxa de ativação'
      WHEN te.sk_category IN ('1.01.96', '1.01.97')
      THEN 'Juros e Multa'
      WHEN te.sk_category = '1.01.90' AND t.project IS NULL
      THEN 'Assinatura'
      WHEN te.sk_category = '1.01.90' AND NOT t.project IS NULL
      THEN 'Garantia'
      WHEN te.sk_category IN ('1.01.02', '1.01.01', '1.01.91', '1.01.92')
      THEN 'Assinatura'
      WHEN te.sk_category IN ('1.05.98')
      THEN 'Rescisão'
      WHEN te.sk_category IN ('1.05.99', '2.11.99', '1.05.95', '2.11.94', '1.05.97', '2.11.97', '1.05.96', '2.11.96', '2.11.98')
      THEN 'Garantia'
      ELSE 'Outros'
    END AS provisional_group,
    CASE
      WHEN te.sk_category LIKE '%1.05.97%' OR te.sk_category LIKE '%2.11.97%'
      THEN TRUE
      ELSE FALSE
    END AS is_danos_imovel,
    IF(p.is_contract AND p.dt_ended IS NULL, TRUE, FALSE) AS is_contract_active,
    p.dt_contract_started,
    p.dt_ended_official AS dt_contract_ended,
    vp.total_package_amount AS valor_pacote
  FROM dw_velo.fact_velo_transaction_entries AS te
  LEFT JOIN dw_velo.dim_velo_transaction AS t
    ON t.sk_transaction = te.sk_transaction
  INNER JOIN dw_velo.dim_velo_transaction_category AS c
    ON te.sk_category = c.sk_category
  LEFT JOIN dw_velo.dim_velo_omie_client AS oc
    ON oc.sk_client = te.sk_omie_client
  LEFT JOIN datalake_velo_omie.cash_flows AS cf
    ON te.sk_transaction = CAST(CONCAT(cf.id_securities, CASE WHEN cf.id_group = 'CONTA_A_RECEBER' THEN '0' ELSE '1' END) AS BIGINT)
  LEFT JOIN dw_velo.fact_velo_propose AS p
    ON te.sk_propose = p.sk_propose
  LEFT JOIN dw_velo.dim_velo_propose_values AS vp
    ON p.sk_propose_values = vp.sk_propose_values
  LEFT JOIN ajuste_omie
    ON ajuste_omie.id_transaction = te.sk_transaction
  WHERE
    t.transaction_type = 'CONTA_A_RECEBER'
), base_omie_ifrs AS (
  SELECT DISTINCT
    'c_omie' AS origin_table_aux,
    'omie' AS origin_table,
    sk_propose,
    sk_propose_20,
    sk_transaction,
    sk_transaction AS sk_key,
    client_cpf_cnpj,
    dt_register,
    dt_due,
    dt_paid,
    dt_paid AS dt_paid_aux,
    CASE
      WHEN dt_paid IS NULL
      THEN DATEDIFF(TO_DATE(CURRENT_DATE), TO_DATE(dt_due))
      WHEN NOT dt_paid IS NULL AND open_amount > 0
      THEN DATEDIFF(TO_DATE(CURRENT_DATE), TO_DATE(dt_due))
      WHEN NOT dt_paid IS NULL AND open_amount <= 0
      THEN DATEDIFF(TO_DATE(dt_paid), TO_DATE(dt_due))
      ELSE -1
    END AS dias_atraso,
    due_amount,
    paid_amount,
    open_amount,
    discount_value,
    description AS bill_item,
    provisional_group,
    is_danos_imovel,
    is_contract_active,
    dt_contract_started,
    dt_contract_ended,
    valor_pacote,
    CAST('false' AS BOOLEAN) AS is_delinquency_renovacao,
    CAST('false' AS BOOLEAN) AS is_perdao_divida
  FROM base_omie
), omie_assinatura AS (
  SELECT
    *
  FROM base_omie_ifrs
  WHERE
    provisional_group IN ('Assinatura', 'Taxa de ativação') AND open_amount > 0
), pagamento_fev AS (
  SELECT
    *
  FROM payment
  WHERE
    DATE_TRUNC('MONTH', dt_paid) >= CAST('2024-01-01' AS DATE)
    AND gateway = 'ASAAS'
    AND payment_category IN ('RECURRING_SUBSCRIPTION', 'ACTIVATION')
    AND status = 'SUCCESS'
), omie_asaas_match AS (
  SELECT
    'c_omie' AS origin_table_aux,
    omie.origin_table,
    omie.sk_propose,
    omie.sk_propose_20,
    omie.sk_transaction,
    omie.sk_transaction AS sk_key,
    omie.client_cpf_cnpj,
    omie.dt_register,
    omie.dt_due,
    CAST(p.dt_paid AS DATE) AS dt_paid,
    CAST(p.dt_paid AS DATE) AS dt_paid_aux,
    CASE
      WHEN p.dt_paid IS NULL
      THEN DATEDIFF(TO_DATE(CURRENT_DATE), TO_DATE(omie.dt_due))
      WHEN NOT p.dt_paid IS NULL AND (
        omie.due_amount - p.value
      ) > 0
      THEN DATEDIFF(TO_DATE(CURRENT_DATE), TO_DATE(omie.dt_due))
      WHEN NOT p.dt_paid IS NULL AND (
        omie.due_amount - p.value
      ) <= 0
      THEN DATEDIFF(TO_DATE(p.dt_paid), TO_DATE(omie.dt_due))
      ELSE -1
    END AS dias_atraso,
    omie.due_amount,
    p.value AS paid_amount,
    (
      omie.due_amount - p.value
    ) AS open_amount,
    omie.discount_value,
    omie.bill_item,
    omie.provisional_group,
    omie.is_danos_imovel,
    omie.is_contract_active,
    omie.dt_contract_started,
    omie.dt_contract_ended,
    omie.valor_pacote,
    omie.is_delinquency_renovacao,
    omie.is_perdao_divida
  FROM omie_assinatura AS omie
  JOIN pagamento_fev AS p
    ON p.id_propose = omie.sk_propose
    AND DATE_TRUNC('MONTH', p.dt_due) = DATE_TRUNC('MONTH', omie.dt_register)
    AND CAST(p.value AS DECIMAL(15, 2)) = CAST(omie.due_amount AS DECIMAL(15, 2))
), transaction_entries AS (
  SELECT
    *
  FROM base_omie AS te
  WHERE
    te.provisional_group IN ('Assinatura', 'Taxa de Ativação', 'Taxa de ativação', 'Garantia', 'Rescisão')
    AND te.open_amount > 0
    AND NOT te.sk_propose IS NULL
    AND te.dt_due < NOW()
    AND te.dt_register < CAST('2023-07-01' AS DATE)
    AND NOT te.sk_transaction IN (
      SELECT
        sk_transaction
      FROM omie_asaas_match
    )
), agreements AS (
  SELECT
    apl.id_propose,
    MIN(apl.dt_confirmed_payment) AS min_dt_paid,
    CAST(SUM(
      apl.value - IF(apl.fine_value IS NULL, 0, apl.fine_value) - IF(apl.interest_value IS NULL, 0, apl.interest_value)
    ) AS DECIMAL(15, 2)) AS agreement_amount
  FROM datalake_rental_guarantee_platform_clean.agreement_payment_legacy AS apl
  WHERE
    apl.status = 'RECEIVED' AND MONTH(TO_DATE(apl.dt_confirmed_payment)) >= 2
  GROUP BY
    1
), transaction_entries_agreement AS (
  SELECT
    te.*,
    a.min_dt_paid,
    a.agreement_amount,
    SUM(open_amount) OVER (PARTITION BY te.sk_propose ORDER BY provisional_group DESC, dt_register ASC, sk_transaction_entry DESC) AS cumulative_open_amount,
    ROW_NUMBER() OVER (PARTITION BY te.sk_propose ORDER BY provisional_group DESC, dt_register ASC, sk_transaction_entry DESC) AS rn
  FROM transaction_entries AS te
  LEFT JOIN agreements AS a
    ON te.sk_propose = a.id_propose
), cumulative_logic_amounts AS (
  SELECT
    *,
    agreement_amount - cumulative_open_amount AS cumulative_agreement_amount
  FROM transaction_entries_agreement
  WHERE
    NOT agreement_amount IS NULL
), final_agreements AS (
  SELECT
    *,
    CASE
      WHEN cumulative_agreement_amount > 0
      THEN open_amount
      WHEN cumulative_agreement_amount < 0
      AND open_amount >= -1 * cumulative_agreement_amount
      THEN (
        open_amount + cumulative_agreement_amount
      )
      WHEN cumulative_agreement_amount < 0
      AND open_amount < -1 * cumulative_agreement_amount
      THEN 0
    END AS paid_amount_agreement
  FROM cumulative_logic_amounts
), aux AS (
  SELECT DISTINCT
    sk_propose,
    sk_transaction,
    client_cpf_cnpj,
    dt_register,
    dt_due,
    CASE WHEN paid_amount_agreement > 0 THEN min_dt_paid ELSE dt_paid END AS dt_paid,
    due_amount,
    paid_amount_agreement,
    (
      paid_amount + paid_amount_agreement
    ) AS paid_amount,
    (
      due_amount - (
        paid_amount + paid_amount_agreement
      )
    ) AS open_amount,
    discount_value,
    description AS bill_item,
    provisional_group,
    is_danos_imovel,
    CAST('false' AS BOOLEAN) AS is_delinquency_renovacao,
    CAST('false' AS BOOLEAN) AS is_perdao_divida
  FROM final_agreements
), omie_pgto_acordos AS (
  SELECT
    'c_omie' AS origin_table_aux,
    'omie' AS origin_table,
    aux.sk_propose,
    CAST(NULL AS INT) AS sk_propose_20,
    sk_transaction,
    sk_transaction AS sk_key,
    client_cpf_cnpj,
    dt_register,
    dt_due,
    dt_paid,
    dt_paid AS dt_paid_aux,
    CASE
      WHEN dt_paid IS NULL
      THEN DATEDIFF(TO_DATE(CURRENT_DATE), TO_DATE(dt_due))
      WHEN NOT dt_paid IS NULL AND open_amount > 0
      THEN DATEDIFF(TO_DATE(CURRENT_DATE), TO_DATE(dt_due))
      WHEN NOT dt_paid IS NULL AND open_amount <= 0
      THEN DATEDIFF(TO_DATE(dt_paid), TO_DATE(dt_due))
      ELSE -1
    END AS dias_atraso,
    due_amount,
    paid_amount,
    open_amount,
    discount_value,
    bill_item,
    provisional_group,
    is_danos_imovel,
    IF(p.is_contract AND p.dt_ended IS NULL, TRUE, FALSE) AS is_contract_active,
    p.dt_contract_started,
    p.dt_ended_official AS dt_contract_ended,
    vp.total_package_amount AS valor_pacote,
    CAST('false' AS BOOLEAN) AS is_delinquency_renovacao,
    CAST('false' AS BOOLEAN) AS is_perdao_divida
  FROM aux
  LEFT JOIN dw_velo.fact_velo_propose AS p
    ON aux.sk_propose = p.sk_propose
  LEFT JOIN dw_velo.dim_velo_propose_values AS vp
    ON p.sk_propose_values = vp.sk_propose_values
  WHERE
    paid_amount > 0
), omie_assinatura AS (
  SELECT
    *
  FROM base_omie_ifrs
  WHERE
    provisional_group IN ('Assinatura', 'Taxa de ativação') AND open_amount <= 0
  UNION
  SELECT
    *
  FROM omie_asaas_match
  UNION
  SELECT
    *
  FROM omie_pgto_acordos
  WHERE
    provisional_group IN ('Assinatura', 'Taxa de ativação')
), omie AS (
  SELECT DISTINCT
    sk_propose,
    oc.client_cpf_cnpj
  FROM dw_velo.fact_velo_transaction_entries AS te
  LEFT JOIN dw_velo.dim_velo_transaction AS t
    ON t.sk_transaction = te.sk_transaction
  INNER JOIN dw_velo.dim_velo_transaction_category AS c
    ON te.sk_category = c.sk_category
  LEFT JOIN dw_velo.dim_velo_omie_client AS oc
    ON oc.sk_client = te.sk_omie_client
  WHERE
    transaction_type = 'CONTA_A_RECEBER'
), sap AS (
  SELECT
    id_business_entity AS sk_propose,
    id_transaction AS sk_transaction,
    CASE WHEN p.is_contract AND p.dt_ended IS NULL THEN TRUE ELSE FALSE END AS is_contract_active,
    p.dt_contract_started,
    p.dt_ended_official AS dt_contract_ended,
    vp.total_package_amount AS valor_pacote,
    CASE
      WHEN (
        accounting_rule LIKE 'velo:a.01%'
        OR accounting_rule LIKE 'velo:at%'
        OR accounting_rule LIKE 'velo:f.01%'
        OR accounting_rule LIKE 'velo:ar.01%'
        OR accounting_rule LIKE 'velo:ac.01%'
        OR accounting_rule LIKE 'velo:AS.01%'
        OR accounting_rule LIKE 'velo:bk.01%'
      )
      THEN 'ASSINATURA'
      WHEN accounting_rule LIKE 'velo:am.01%'
      OR accounting_rule LIKE 'velo:r.01%'
      OR accounting_rule LIKE 'velo:an.01%'
      OR accounting_rule LIKE 'velo:bi.%'
      OR accounting_rule LIKE 'Velo:y.01%'
      OR accounting_rule LIKE 'velo:ap.01%'
      OR accounting_rule LIKE 'velo:ad.01%'
      OR accounting_rule LIKE 'velo:aq.01%'
      OR accounting_rule LIKE 'velo:bj.01%'
      OR accounting_rule LIKE 'Velo:ab.01%'
      THEN 'GARANTIA'
    END AS accounting_rule,
    dt_due,
    dt_reference AS dt_paid,
    SUM(debit_credit) AS valor_pago
  FROM datalake_accounting_funnel.ledger AS sap
  LEFT JOIN dw_velo.fact_velo_propose AS p
    ON p.sk_propose = sap.id_business_entity
  LEFT JOIN dw_velo.dim_velo_propose_values AS vp
    ON p.sk_propose_values = vp.sk_propose_values
  WHERE
    dt_reference BETWEEN CAST('2023-09-01' AS DATE) AND CAST('2023-09-30' AS DATE)
    AND credit = 0
    AND (
      account_name IN ('Títulos recebidos via cartão de crédito', 'Itaú Ag. 8792 Conta 49458-8')
      OR account_number IN ('113070', '110354')
    )
  GROUP BY
    1,
    2,
    3,
    4,
    5,
    6,
    7,
    8,
    9
), base_sap_ifrs AS (
  SELECT DISTINCT
    'd_sap' AS origin_table_aux,
    'sap' AS origin_table,
    sap.sk_propose,
    CAST(NULL AS INT) AS sk_propose_20,
    sap.sk_transaction,
    sap.sk_transaction AS sk_key,
    omie.client_cpf_cnpj,
    NULL AS dt_register,
    sap.dt_due,
    sap.dt_paid,
    sap.dt_paid AS dt_paid_aux,
    NULL AS dias_atraso,
    0 AS due_amount,
    valor_pago AS paid_amount,
    0 AS open_amount,
    0 AS discount_value,
    'transacao SAP' AS bill_item,
    accounting_rule AS provisional_group,
    NULL AS is_danos_imovel,
    sap.is_contract_active,
    sap.dt_contract_started,
    sap.dt_contract_ended,
    sap.valor_pacote,
    CAST('false' AS BOOLEAN) AS is_delinquency_renovacao,
    CAST('false' AS BOOLEAN) AS is_perdao_divida
  FROM sap
  JOIN omie
    ON omie.sk_propose = sap.sk_propose
  WHERE
    accounting_rule IN ('GARANTIA', 'ASSINATURA')
), payment_asaas_sap AS (
  SELECT DISTINCT
    s.id_business_entity AS sk_propose,
    p.id AS sk_transaction,
    s.status AS sent_status,
    p.billing_type,
    CAST(p.ts_created AS DATE) AS dt_register,
    CAST(p.ts_due AS DATE) AS dt_due,
    CAST(s.ts_created AS DATE) AS dt_paid,
    DATEDIFF(TO_DATE(CAST(s.ts_created AS DATE)), TO_DATE(CAST(p.ts_due AS DATE))) AS dias_atraso,
    p.value AS due_amount,
    p.value AS paid_amount,
    0 AS open_amount,
    0 AS discount_value,
    per.document AS client_cpf_cnpj,
    'Assinatura' AS provisional_group,
    FALSE AS is_danos_imovel,
    CASE WHEN pr.is_contract AND pr.dt_ended IS NULL THEN TRUE ELSE FALSE END AS is_contract_active,
    pr.dt_contract_started,
    pr.dt_ended_official AS dt_contract_ended,
    vp.total_package_amount AS valor_pacote
  FROM datalake_rental_guarantee_platform_clean.payment AS p
  LEFT JOIN datalake_rental_guarantee_platform_clean.sap AS s
    ON s.id_finance_entity = p.id
  LEFT JOIN dw_velo.fact_velo_propose AS pr
    ON p.id_propose = pr.sk_propose
  LEFT JOIN dw_velo.bridge_velo_propose_person AS ps
    ON p.id_propose = ps.sk_propose AND ps.is_primary_person
  LEFT JOIN dw_velo.dim_velo_propose_person AS per
    ON per.sk_person = ps.sk_person
  LEFT JOIN dw_velo.dim_velo_propose_values AS vp
    ON pr.sk_propose_values = vp.sk_propose_values
  WHERE
    (
      s.trigger = 'TRIGGER_ACTIVATION_RECURRENCE_ASAAS'
      OR s.trigger = 'TRIGGER_ACTIVATION_RECURRENCE_ASAAS_CHARGEBACK'
      OR s.trigger = 'TRIGGER_ACTIVATION_RECURRENCE_WITH_FINE_INTEREST_ASAAS'
    )
    AND s.status = 'SUCCESS'
), rn AS (
  SELECT
    *,
    ROW_NUMBER() OVER (PARTITION BY sk_transaction ORDER BY dt_due) AS rn
  FROM payment_asaas_sap
), base_payment_asaas_sap AS (
  SELECT
    'b_payment' AS origin_table_aux,
    'payment' AS origin_table,
    sk_propose,
    CAST(NULL AS INT) AS sk_propose_20,
    sk_transaction,
    sk_transaction AS sk_key,
    client_cpf_cnpj,
    dt_register,
    dt_due,
    dt_paid,
    dt_paid AS dt_paid_aux,
    dias_atraso,
    due_amount,
    paid_amount,
    open_amount,
    discount_value,
    'Assinatura' AS bill_item,
    provisional_group,
    is_danos_imovel,
    is_contract_active,
    dt_contract_started,
    dt_contract_ended,
    valor_pacote,
    CAST('false' AS BOOLEAN) AS is_delinquency_renovacao,
    CAST('false' AS BOOLEAN) AS is_perdao_divida
  FROM rn
  WHERE
    rn = 1
), ajuste_pagamento AS (
  SELECT
    sk_payment,
    IF(status.desc_lvl_1 IN ('SUCCESS', 'REFUNDED', 'CHARGEBACK'), pay.dt_paid, NULL) AS dt_paid,
    CASE
      WHEN status.desc_lvl_1 IN ('SUCCESS', 'REFUNDED', 'CHARGEBACK')
      OR NOT pay.dt_paid IS NULL
      THEN pay.due_amount
      ELSE 0
    END AS paid_amount
  FROM dw_velo.fact_velo_payment AS pay
  LEFT JOIN dw_velo.dim_velo_junk AS status
    ON status.sk_junk = pay.sk_status
  WHERE
    pay.is_occurrence = FALSE
), casos_reembolso AS (
  SELECT DISTINCT
    pay.sk_payment
  FROM dw_velo.fact_velo_payment AS pay
  LEFT JOIN dw_velo.fact_velo_propose AS pr
    ON pay.sk_propose = pr.sk_propose
  LEFT JOIN dw_velo.dim_velo_junk AS status
    ON status.sk_junk = pay.sk_status
  LEFT JOIN dw_velo.dim_velo_junk AS gateway
    ON gateway.sk_junk = pay.sk_payment_gateway
  LEFT JOIN dw_velo.dim_velo_junk AS billing
    ON billing.sk_junk = pay.sk_billing_type
  WHERE
    NOT pr.dt_ended IS NULL
    AND billing.desc_lvl_1 = 'ANNUAL_CREDIT_CARD'
    AND status.desc_lvl_1 = 'REFUNDED'
), base AS (
  SELECT DISTINCT
    pay.sk_propose,
    pay.sk_payment AS sk_transaction,
    ps.is_primary_person,
    per.document AS client_cpf_cnpj,
    pay.dt_created AS dt_register,
    pay.dt_due,
    ajuste_pagamento.dt_paid,
    CASE
      WHEN NOT ajuste_pagamento.dt_paid IS NULL
      AND DATEDIFF(TO_DATE(ajuste_pagamento.dt_paid), TO_DATE(pay.dt_due)) <= 0
      THEN 0
      WHEN pay.is_paid_late
      THEN DATEDIFF(TO_DATE(ajuste_pagamento.dt_paid), TO_DATE(pay.dt_due))
      WHEN ajuste_pagamento.dt_paid IS NULL AND pay.dt_due < CURRENT_DATE
      THEN DATEDIFF(TO_DATE(CURRENT_DATE), TO_DATE(pay.dt_due))
    END AS dias_atraso,
    pay.due_amount,
    ajuste_pagamento.paid_amount AS paid_amount,
    pay.due_amount - ajuste_pagamento.paid_amount AS open_amount,
    0 AS discount_value,
    'Assinatura' AS provisional_group,
    FALSE AS is_danos_imovel,
    IF(pr.is_contract AND pr.dt_ended IS NULL, TRUE, FALSE) AS is_contract_active,
    pr.dt_contract_started,
    pr.dt_ended_official AS dt_contract_ended,
    vp.total_package_amount AS valor_pacote,
    gateway.desc_lvl_1 AS gateway,
    status.desc_lvl_1 AS status_payment
  FROM dw_velo.fact_velo_payment AS pay
  LEFT JOIN ajuste_pagamento
    ON ajuste_pagamento.sk_payment = pay.sk_payment
  LEFT JOIN dw_velo.fact_velo_propose AS pr
    ON pay.sk_propose = pr.sk_propose
  LEFT JOIN dw_velo.bridge_velo_propose_person AS ps
    ON pay.sk_propose = ps.sk_propose AND ps.is_primary_person
  LEFT JOIN dw_velo.dim_velo_propose_person AS per
    ON per.sk_person = ps.sk_person
  LEFT JOIN dw_velo.dim_velo_propose_values AS vp
    ON pr.sk_propose_values = vp.sk_propose_values
  LEFT JOIN dw_velo.dim_velo_junk AS status
    ON status.sk_junk = pay.sk_status
  LEFT JOIN dw_velo.dim_velo_junk AS gateway
    ON gateway.sk_junk = pay.sk_payment_gateway
  LEFT JOIN dw_velo.dim_velo_junk AS billing
    ON billing.sk_junk = pay.sk_billing_type
  LEFT JOIN casos_reembolso AS cr
    ON cr.sk_payment = pay.sk_payment
  WHERE
    pay.is_occurrence = FALSE
    AND pay.is_legacy = FALSE
    AND gateway.desc_lvl_1 <> 'ASAAS'
    AND status.desc_lvl_1 = 'SUCCESS'
    AND NOT pr.dt_contract_started IS NULL
    AND cr.sk_payment IS NULL
), rn AS (
  SELECT
    *,
    ROW_NUMBER() OVER (PARTITION BY sk_transaction ORDER BY dt_due) AS rn
  FROM base
), base_assinatura_3_0 AS (
  SELECT
    'b_payment' AS origin_table_aux,
    'payment' AS origin_table,
    sk_propose,
    CAST(NULL AS INT) AS sk_propose_20,
    sk_transaction,
    sk_transaction AS sk_key,
    client_cpf_cnpj,
    dt_register,
    dt_due,
    dt_paid,
    dt_paid AS dt_paid_aux,
    dias_atraso,
    due_amount,
    paid_amount,
    open_amount,
    discount_value,
    'Assinatura' AS bill_item,
    provisional_group,
    is_danos_imovel,
    is_contract_active,
    dt_contract_started,
    dt_contract_ended,
    valor_pacote,
    CAST('false' AS BOOLEAN) AS is_delinquency_renovacao,
    CAST('false' AS BOOLEAN) AS is_perdao_divida
  FROM rn
  WHERE
    rn = 1
), cpf_cnpj_person AS (
  SELECT
    sk_propose,
    document,
    ROW_NUMBER() OVER (PARTITION BY sk_propose ORDER BY document) AS rn
  FROM dw_velo.bridge_velo_propose_person AS ps
  LEFT JOIN dw_velo.dim_velo_propose_person AS per
    ON per.sk_person = ps.sk_person
  WHERE
    ps.is_primary_person
), delinquency_entry AS (
  SELECT
    d.id AS id_delinquency,
    entry.id AS id_delinquency_entry,
    entry.bill_item,
    entry.value AS entry_value,
    CASE
      WHEN d.amount_paid - d.original_value >= 0
      THEN entry.value
      WHEN d.amount_paid > 0
      THEN (
        entry.value / d.original_value
      ) * d.amount_paid
    END AS paid_amount_entry
  FROM datalake_rental_guarantee_platform_clean.delinquency AS d
  LEFT JOIN datalake_rental_guarantee_platform_clean.delinquency_entry AS entry
    ON d.id = entry.id_delinquency
  WHERE
    is_active = TRUE AND id_type IN (1, 2)
), base_inadimplecia_assinatura AS (
  SELECT DISTINCT
    d.id_propose AS sk_propose,
    d.id AS sk_delinquency,
    entry.id_delinquency_entry AS sk_delinquency_entry,
    d.id_status,
    d.id_type,
    doc.document AS client_cpf_cnpj,
    DATE_TRUNC('DAY', d.ts_created) AS dt_register,
    d.dt_due,
    d.dt_paid,
    IF(d.id_status = 7, d.dt_due, d.dt_paid) AS dt_paid_aux,
    d.original_value AS due_amount_delinquency,
    d.amount_paid AS paid_amount_delinquency,
    IF(
      d.id_status IN (3, 7) OR d.original_value - d.amount_paid < 0,
      0,
      d.original_value - d.amount_paid
    ) AS net_amount_delinquency,
    IF(
      d.id_status IN (3, 7) AND amount_paid < original_value,
      original_value - amount_paid,
      NULL
    ) AS discount_value_delinquency,
    IF(d.id_type IN (0, 4, 5, 6), d.original_value, entry.entry_value) AS due_amount_entry,
    IF(d.id_type IN (0, 4, 5, 6), d.amount_paid, entry.paid_amount_entry) AS paid_amount_entry,
    CASE
      WHEN d.id_status IN (3, 7) OR d.original_value - d.amount_paid < 0
      THEN 0
      WHEN d.id_type IN (0, 4, 5, 6)
      THEN d.original_value - d.amount_paid
      ELSE (
        entry.entry_value - COALESCE(entry.paid_amount_entry, 0)
      )
    END AS net_amount_entry,
    CASE
      WHEN d.id_status IN (3, 7)
      AND d.id_type IN (0, 4, 5, 6)
      AND amount_paid < original_value
      THEN ABS(original_value - amount_paid)
      WHEN d.id_status IN (3, 7)
      AND COALESCE(entry.paid_amount_entry, 0) < entry.entry_value
      THEN ABS(entry.entry_value - COALESCE(entry.paid_amount_entry, 0))
    END AS discount_value_entry,
    CASE
      WHEN id_type IN (0, 4, 5, 6)
      THEN 'Assinatura'
      WHEN id_type = 1
      THEN 'Garantia'
      WHEN id_type = 2
      THEN 'Rescisão'
    END AS provisional_group,
    IF(id_type = 4, TRUE, FALSE) AS is_delinquency_renovacao,
    IF(d.id_status = 7, TRUE, FALSE) AS is_perdao_divida,
    entry.bill_item,
    IF(entry.bill_item = 'REALTY_DAMAGE', TRUE, FALSE) AS is_danos_imovel,
    IF(p.is_contract AND p.dt_ended IS NULL, TRUE, FALSE) AS is_contract_active,
    p.dt_contract_started,
    p.dt_ended_official AS dt_contract_ended,
    vp.total_package_amount AS valor_pacote
  FROM datalake_rental_guarantee_platform_clean.delinquency AS d
  LEFT JOIN delinquency_entry AS entry
    ON d.id = entry.id_delinquency
  LEFT JOIN datalake_rental_guarantee_platform_clean.delinquency_has_agreement AS da
    ON d.id = da.id_delinquency
  LEFT JOIN datalake_rental_guarantee_platform_clean.agreement AS a
    ON da.id_agreement = a.id
  LEFT JOIN datalake_rental_guarantee_platform_clean.agreement_payment AS ap
    ON ap.id_agreement = a.id
  LEFT JOIN cpf_cnpj_person AS doc
    ON doc.sk_propose = d.id_propose AND rn = 1
  LEFT JOIN dw_velo.fact_velo_propose AS p
    ON d.id_propose = p.sk_propose
  LEFT JOIN dw_velo.dim_velo_propose_values AS vp
    ON p.sk_propose_values = vp.sk_propose_values
  WHERE
    is_active = TRUE
), base_inadimplecia_ifrs_assinatura AS (
  SELECT DISTINCT
    'a_delinquency' AS origin_table_aux,
    'delinquency' AS origin_table,
    sk_propose,
    CAST(NULL AS INT) AS sk_propose_20,
    COALESCE(sk_delinquency_entry, sk_delinquency) AS sk_transaction,
    sk_delinquency AS sk_key,
    client_cpf_cnpj,
    dt_register,
    dt_due,
    dt_paid,
    dt_paid_aux,
    CASE
      WHEN dt_paid IS NULL
      THEN DATEDIFF(TO_DATE(CURRENT_DATE), TO_DATE(dt_due))
      WHEN NOT dt_paid IS NULL AND net_amount_entry > 0
      THEN DATEDIFF(TO_DATE(CURRENT_DATE), TO_DATE(dt_due))
      WHEN NOT dt_paid IS NULL AND net_amount_entry <= 0
      THEN DATEDIFF(TO_DATE(dt_paid), TO_DATE(dt_due))
      ELSE -1
    END AS dias_atraso,
    due_amount_entry AS due_amount,
    paid_amount_entry AS paid_amount,
    net_amount_entry AS open_amount,
    discount_value_entry AS discount_value,
    bill_item,
    provisional_group,
    is_danos_imovel,
    is_contract_active,
    dt_contract_started,
    dt_contract_ended,
    valor_pacote,
    is_delinquency_renovacao,
    is_perdao_divida
  FROM base_inadimplecia_assinatura
), base_unificada AS (
  SELECT
    *
  FROM omie_assinatura
  WHERE
    provisional_group IN ('Assinatura', 'Taxa de Ativação', 'Taxa de ativação')
  UNION
  SELECT
    *
  FROM base_sap_ifrs
  WHERE
    provisional_group IN ('ASSINATURA')
  UNION
  SELECT
    *
  FROM base_payment_asaas_sap
  UNION
  SELECT
    *
  FROM base_assinatura_3_0
  UNION
  SELECT
    *
  FROM base_inadimplecia_ifrs_assinatura
  WHERE
    provisional_group IN ('Assinatura')
), deduplicao AS (
  SELECT
    *,
    ROW_NUMBER() OVER (PARTITION BY sk_propose, DATE_TRUNC('MONTH', CAST(dt_due AS DATE)), due_amount ORDER BY open_amount ASC, dt_paid_aux DESC, origin_table_aux ASC) AS rn
  FROM base_unificada
), base_assinatura_ifrs_sem_repasse AS (
  SELECT
    origin_table,
    sk_propose,
    sk_propose_20,
    NULL AS id_bill,
    sk_transaction,
    sk_key,
    client_cpf_cnpj,
    dt_register,
    dt_due,
    NULL AS dt_due_billing_report,
    dt_paid,
    dias_atraso,
    CAST(due_amount AS DOUBLE) AS due_amount,
    CAST(paid_amount AS DOUBLE) AS paid_amount,
    CAST(open_amount AS DOUBLE) AS open_amount,
    CAST(discount_value AS DOUBLE) AS discount_value,
    bill_item,
    provisional_group,
    is_danos_imovel,
    is_contract_active,
    dt_contract_started,
    dt_contract_ended,
    valor_pacote,
    is_delinquency_renovacao,
    is_perdao_divida
  FROM deduplicao
  WHERE
    rn = 1
), sap AS (
  SELECT
    id_finance_entity AS id_fatura,
    id_finance_entity_entry AS id_contract,
    credit AS mensalidade_por_contrato
  FROM datalake_accounting_funnel.ledger
  WHERE
    (
      account_number = '113009' OR account_name IN ('Duplicatas a Receber VELO')
    )
    AND debit = 0
), cpf_cnpj_person AS (
  SELECT
    sk_propose,
    document,
    ROW_NUMBER() OVER (PARTITION BY sk_propose ORDER BY document) AS rn
  FROM dw_velo.bridge_velo_propose_person AS ps
  LEFT JOIN dw_velo.dim_velo_propose_person AS per
    ON per.sk_person = ps.sk_person
  WHERE
    ps.is_primary_person
), recebimento_por_contrato_boleto_billing /*     b.status NOT IN ('WRITTEN_DOWN') */ /*     AND CONCAT(b.status,i.status) NOT IN ('OVERDUECANCELED') */ AS (
  SELECT DISTINCT
    c.uuid_company AS imob_uuid,
    imob.broker_name,
    b.id AS id_bill,
    c.id AS imob_id,
    i.id AS fatura_id,
    i.status AS fatura_status,
    CAST(i.ts_created AS DATE) AS dt_criacao_invoice,
    ADD_MONTHS(
      CAST(CONCAT(CAST(i.accrual_year AS STRING), '-', CAST((
        i.accrual_month
      ) AS STRING), '-', '01') AS DATE),
      1
    ) AS dt_ref_boleto,
    i.dt_due AS fatura_vencimento,
    i.total_amount AS fatura_valor,
    COALESCE(sap.id_contract, e.propose) AS sk_propose,
    COALESCE(sap.mensalidade_por_contrato, e.amount) AS mensalidade_por_contrato,
    IF(
      b.status IN ('PAID', 'PAID_AFTER_DUE_DATE'),
      COALESCE(sap.mensalidade_por_contrato, e.amount),
      0
    ) AS paid_amount,
    CAST(b.ts_paid AS DATE) AS boleto_compensando_em,
    CAST(b.ts_created AS DATE) AS dt_boleto_created,
    b.status AS boleto_status,
    doc.document AS client_cpf_cnpj,
    fp.dt_contract_started,
    fp.dt_ended_official AS dt_contract_ended,
    IF(fp.is_contract AND fp.dt_ended IS NULL, TRUE, FALSE) AS is_contract_active,
    vp.total_package_amount AS valor_pacote,
    ROW_NUMBER() OVER (PARTITION BY COALESCE(sap.id_contract, e.propose), ADD_MONTHS(
      CAST(CONCAT(CAST(i.accrual_year AS STRING), '-', CAST((
        i.accrual_month
      ) AS STRING), '-', '01') AS DATE),
      1
    ) ORDER BY CAST(b.ts_paid AS DATE) DESC, CAST(b.ts_created AS DATE) DESC) AS rn
  FROM datalake_rental_guarantee_platform_clean.billing_report AS i
  LEFT JOIN datalake_rental_guarantee_platform_clean.bill AS b
    ON b.id = i.id_bill
  LEFT JOIN datalake_rental_guarantee_platform_clean.entry AS e
    ON e.id_billing_report = i.id
  LEFT JOIN datalake_rental_guarantee_platform_clean.company AS c
    ON c.id = i.id_company
  LEFT JOIN dw_velo.dim_velo_broker AS imob
    ON imob.sk_broker = c.id
  LEFT JOIN dw_velo.fact_velo_propose AS fp
    ON fp.sk_propose = e.propose
  LEFT JOIN sap
    ON sap.id_fatura = CAST(i.id AS STRING)
    AND sap.id_contract = CAST(fp.sk_propose AS STRING)
  LEFT JOIN dw_velo.dim_velo_propose_values AS vp
    ON fp.sk_propose_values = vp.sk_propose_values
  LEFT JOIN cpf_cnpj_person AS doc
    ON doc.sk_propose = fp.sk_propose AND rn = 1
  WHERE
    NOT CONCAT(b.status, i.status) IN ('WRITTEN_DOWNCANCELED')
), repasse_direto AS (
  SELECT
    'invoice' AS origin_table,
    sk_propose,
    CAST(NULL AS INT) AS sk_propose_20,
    id_bill,
    CONCAT(sk_propose, REPLACE(dt_ref_boleto, '-', '')) AS sk_transaction,
    CONCAT(sk_propose, fatura_id) AS sk_key,
    client_cpf_cnpj,
    dt_ref_boleto AS dt_register,
    dt_ref_boleto AS dt_due,
    fatura_vencimento AS dt_due_billing_report,
    boleto_compensando_em AS dt_paid,
    IF(
      DATEDIFF(TO_DATE(COALESCE(boleto_compensando_em, CURRENT_DATE)), TO_DATE(fatura_vencimento)) < 0,
      0,
      DATEDIFF(TO_DATE(COALESCE(boleto_compensando_em, CURRENT_DATE)), TO_DATE(fatura_vencimento))
    ) AS dias_de_atraso,
    mensalidade_por_contrato AS due_amount,
    paid_amount,
    (
      mensalidade_por_contrato - paid_amount
    ) AS open_amount,
    NULL AS discount_value,
    NULL AS bill_item,
    'Assinatura' AS provisional_group,
    NULL AS is_danos_imovel,
    is_contract_active,
    dt_contract_started,
    dt_contract_ended,
    valor_pacote,
    CAST('false' AS BOOLEAN) AS is_delinquency_renovacao,
    CAST('false' AS BOOLEAN) AS is_perdao_divida
  FROM recebimento_por_contrato_boleto_billing
  WHERE
    rn = 1
), unificada AS (
  SELECT
    *
  FROM base_assinatura_ifrs_sem_repasse
  UNION
  SELECT
    *
  FROM repasse_direto
), unificada_aux AS (
  SELECT
    *,
    ROW_NUMBER() OVER (PARTITION BY sk_propose, DATE_TRUNC('MONTH', CAST(dt_due AS DATE)), ROUND(due_amount) ORDER BY open_amount ASC, dt_paid DESC) AS rn
  FROM unificada
), base_final_unificada AS (
  SELECT
    origin_table,
    sk_propose,
    sk_propose_20,
    sk_transaction,
    sk_key,
    id_bill,
    client_cpf_cnpj,
    dt_register,
    dt_due,
    dt_due_billing_report,
    dt_paid,
    IF(dias_atraso < 0, 0, dias_atraso) AS dias_atraso,
    CAST(due_amount AS DOUBLE) AS due_amount,
    CAST(paid_amount AS DOUBLE) AS paid_amount,
    CAST(open_amount AS DOUBLE) AS open_amount,
    CAST(discount_value AS DOUBLE) AS discount_value,
    bill_item,
    provisional_group,
    is_danos_imovel,
    is_contract_active,
    dt_contract_started,
    dt_contract_ended,
    valor_pacote,
    is_delinquency_renovacao,
    is_perdao_divida
  FROM unificada_aux
  WHERE
    rn = 1
)
SELECT
  origin_table,
  sk_propose,
  sk_propose_20,
  sk_transaction,
  sk_key,
  id_bill,
  client_cpf_cnpj,
  dt_register,
  dt_due,
  dt_due_billing_report,
  dt_paid,
  dias_atraso,
  CAST(due_amount AS DOUBLE) AS due_amount,
  CAST(paid_amount AS DOUBLE) AS paid_amount,
  CAST(open_amount AS DOUBLE) AS open_amount,
  CAST(discount_value AS DOUBLE) AS discount_value,
  bill_item,
  provisional_group,
  is_danos_imovel,
  is_contract_active,
  dt_contract_started,
  dt_contract_ended,
  valor_pacote,
  is_delinquency_renovacao,
  is_perdao_divida,
  NOW() AS ts_load
FROM base_final_unificada
WHERE
  NOT sk_propose IS NULL