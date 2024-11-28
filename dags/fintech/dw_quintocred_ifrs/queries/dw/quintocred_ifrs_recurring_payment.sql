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
    FROM
        dw_velo.fact_velo_payment p
    LEFT JOIN
        dw_velo.dim_velo_junk status_pay
            ON status_pay.sk_junk = p.sk_status
    LEFT JOIN
        dw_velo.dim_velo_junk gateway
            ON gateway.sk_junk = p.sk_payment_gateway
    LEFT JOIN
        dw_velo.dim_velo_junk billing
            ON billing.sk_junk = p.sk_billing_type
    LEFT JOIN
        dw_velo.dim_velo_junk payment_category
            ON p.sk_payment_category = payment_category.sk_junk
),
ajuste_omie AS (
    WITH new AS (
        WITH cte_categories_details_merged AS (
            (
            SELECT
                cfc.id_securities,
                cfc.id_group,
                cfc.id_category,
                cfc.category_percentage,
                cfc.category_value
            FROM
                datalake_velo_omie.cash_flows_categories AS cfc
            )
            UNION ALL
            (
            SELECT
                cf.id_securities,
                cf.id_group,
                cf.id_category,
                100 AS category_percentage,
                cf.due_amount AS category_value
            FROM
                datalake_velo_omie.cash_flows AS cf
            WHERE
                categories iS NULL
            )
        ),
        cte_transactions AS (
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
                    WHEN c2.description IN ('Alugueis', 'Condominio') THEN 'ongoing'
                    WHEN c2.description IN ('Danos ao Imóvel', 'Rescisão') THEN 'rescisão'
                    ELSE NULL
                END AS transaction_purpose,
                cte_cat.category_percentage AS percent_amount_from_transaction,
                SIGN(cf.due_amount) * cte_cat.category_value AS due_amount,
                cte_cat.category_percentage/100 * cf.paid_amount AS paid_amount,
                c1.account_tag = 'Garantia Locaticia' AS is_occurency,
                COALESCE(CAST(SPLIT(cf.id_installment, '/')[0] AS DOUBLE),0) AS installment,
                COALESCE(CAST(SPLIT(cf.id_installment, '/')[1] AS DOUBLE),0) AS total_installments,
                SUM(CASE
                        WHEN cf.id_group = 'CONTA_A_RECEBER' AND cf.id_project IS NOT NULL THEN cf.securities_value
                        ELSE 0
                    END) OVER (PARTITION BY cf.id_project, cf.dt_register) > 0
                    AND cf.id_project IS NOT NULL AS is_project_receivable_created,
                SUM(CASE
                        WHEN cf.id_group = 'CONTA_A_RECEBER' AND cf.id_project IS NOT NULL THEN cf.securities_value
                        ELSE 0
                    END) OVER (PARTITION BY cf.id_project, cf.dt_register)
                >=
                SUM(CASE
                        WHEN cf.id_group = 'CONTA_A_PAGAR' AND cf.id_project IS NOT NULL THEN cf.securities_value
                        ELSE 0
                    END) OVER (PARTITION BY cf.id_project, cf.dt_register)
                    AND cf.id_project IS NOT NULL AS is_project_receivable_greater_than_payable,
                cf.dt_issue,
                cf.dt_register,
                cf.dt_due,
                cf.dt_payment AS dt_paid,
                cf.ts_created,
                cf.ts_modified
            FROM
                datalake_velo_omie.cash_flows AS cf
            LEFT JOIN
                cte_categories_details_merged AS cte_cat
                ON cte_cat.id_securities = cf.id_securities
                AND cte_cat.id_group = cf.id_group
            LEFT JOIN
                datalake_velo_omie_clean.projects AS p
                ON cf.id_project = p.id_project
            LEFT JOIN
                datalake_velo_omie_clean.categories AS c1
                ON c1.id_category = cte_cat.id_category
            LEFT JOIN
                datalake_velo_omie_clean.categories AS c2
                ON c2.id_category = cf.id_category
            LEFT JOIN
                datalake_velo_omie_clean.bank_account AS ba
                ON ba.id_account = cf.id_bank_account
            WHERE
                cf.id_group IN ('CONTA_A_PAGAR', 'CONTA_A_RECEBER')
                AND cf.status <> 'CANCELADO'
        )
        SELECT
            CAST(CONCAT(ct.id_securities, REPLACE(ct.id_category, '.', '')) AS BIGINT) AS id_transaction_entry,
            CAST(CONCAT(ct.id_securities, CASE WHEN ct.transaction_type = 'CONTA_A_RECEBER' THEN '0' ELSE '1' END) AS BIGINT) AS id_transaction,
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
        FROM
            cte_transactions AS ct
    )
    SELECT
        new.id_propose AS id_propose_new,
        old.id_propose AS id_propose_old,
        old.*
    FROM
        datalake_velo.transaction_entries old
    FULL OUTER JOIN
        new
            ON new.id_transaction_entry = old.id_transaction_entry
    WHERE
        new.id_propose<>old.id_propose
),
base_omie AS (
    SELECT
        te.sk_transaction_entry,
        t.sk_transaction,
        te.sk_propose,
        COALESCE(ajuste_omie.id_propose_new, te.sk_propose) AS sk_propose_20,
        te.percent_amount_from_transaction,
        te.due_amount,
        (te.paid_amount-cf.discount_value) AS paid_amount,
        (te.due_amount-cf.discount_value)-(te.paid_amount-cf.discount_value) AS open_amount,
        cf.discount_value,
        te.dt_register,
        te.dt_due,
        te.dt_paid,
        te.sk_omie_client,
        oc.corporate_name,
        oc.name_doing_business_as,
        oc.client_cpf_cnpj,
        oc.corporate_name||' '||oc.client_cpf_cnpj AS chave_assinatura,
        COALESCE(t.project,(oc.corporate_name||' '||oc.client_cpf_cnpj)) AS chave,
        t.project,
        t.transaction_type,
        c.description,
        CASE
            WHEN te.sk_category = '1.01.03' THEN 'Taxa de ativação'
            WHEN te.sk_category IN ('1.01.96','1.01.97') THEN 'Juros e Multa'
            WHEN te.sk_category = '1.01.90' AND t.project IS NULL THEN 'Assinatura'
            WHEN te.sk_category = '1.01.90' AND t.project IS NOT NULL THEN 'Garantia'
            WHEN te.sk_category IN ('1.01.02','1.01.01','1.01.91','1.01.92') THEN 'Assinatura'
            WHEN te.sk_category IN ('1.05.98') THEN 'Rescisão'
            WHEN te.sk_category IN ('1.05.99','2.11.99','1.05.95','2.11.94','1.05.97','2.11.97','1.05.96','2.11.96','2.11.98') THEN 'Garantia'
            ELSE 'Outros'
        END AS provisional_group,
        CASE
            WHEN te.sk_category LIKE '%1.05.97%'
            OR te.sk_category LIKE '%2.11.97%'
            THEN true ELSE false
        END AS is_danos_imovel,
        IF(DATE_DIFF(COALESCE(te.dt_paid,current_date ), te.dt_due)<0,0,DATE_DIFF(COALESCE(te.dt_paid,current_date ), te.dt_due)) AS dias_atraso,
        IF (p.is_contract AND p.dt_ended IS NULL, true, false) AS is_contract_active,
        p.dt_contract_started,
        p.dt_ended_official AS dt_contract_ended,
        vp.total_package_amount AS valor_pacote
    FROM
        dw_velo.fact_velo_transaction_entries AS te
    LEFT JOIN
        dw_velo.dim_velo_transaction AS t
            ON t. sk_transaction = te.sk_transaction
    INNER JOIN
        dw_velo.dim_velo_transaction_category AS c
            ON te.sk_category = c.sk_category
    LEFT JOIN
        dw_velo.dim_velo_omie_client AS oc
            ON oc.sk_client = te.sk_omie_client
    LEFT JOIN
        datalake_velo_omie.cash_flows cf
            ON te.sk_transaction = CAST(CONCAT(cf.id_securities, CASE WHEN cf.id_group = 'CONTA_A_RECEBER' THEN '0' ELSE '1' END) AS BIGINT)
    LEFT JOIN
        dw_velo.fact_velo_propose	p
            ON te.sk_propose = p.sk_propose
    LEFT JOIN
        dw_velo.dim_velo_propose_values vp
            ON p.sk_propose_values = vp.sk_propose_values
    LEFT JOIN
        ajuste_omie
            ON ajuste_omie.id_transaction = te.sk_transaction
    WHERE
        t.transaction_type = 'CONTA_A_RECEBER'
),
base_omie_ifrs AS (
    SELECT DISTINCT
        "c_omie" AS origin_table_aux,
        "omie" AS origin_table,
        sk_propose,
        sk_propose_20,
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
        description AS bill_item,
        provisional_group,
        is_danos_imovel,
        is_contract_active,
        dt_contract_started,
        dt_contract_ended,
        valor_pacote,
        CAST('false' AS BOOLEAN) AS is_delinquency_renovacao,
        CAST('false' AS BOOLEAN) AS is_perdao_divida
    FROM
        base_omie
),
omie_asaas_match AS (
    WITH omie_assinatura AS (
        SELECT *
        FROM
            base_omie_ifrs
        WHERE
            provisional_group IN ('Assinatura', 'Taxa de ativação')
            AND open_amount>0
    )
   ,pagamento_fev AS (
        SELECT *
        FROM
            payment
        WHERE
            DATE_TRUNC('month',dt_paid ) >= DATE('2024-01-01')
            AND gateway = 'ASAAS'
            AND payment_category IN ('RECURRING_SUBSCRIPTION','ACTIVATION')
            AND status = 'SUCCESS'
    )
    SELECT
        "c_omie" AS origin_table_aux,
        omie.origin_table,
        omie.sk_propose,
        omie.sk_propose_20,
        omie.sk_transaction,
        omie.sk_transaction AS sk_key,
        omie.client_cpf_cnpj,
        omie.dt_register,
        omie.dt_due,
        DATE(p.dt_paid) AS dt_paid,
        DATE(p.dt_paid)dt_paid_aux,
        IF(DATE_DIFF(COALESCE(DATE(p.dt_paid),current_date ), omie.dt_due)<0,0,DATE_DIFF(COALESCE(DATE(p.dt_paid),current_date ), omie.dt_due)) AS dias_atraso,
        omie.due_amount,
        p.value AS paid_amount,
        (omie.due_amount - p.value) AS open_amount,
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
    FROM
        omie_assinatura omie
    JOIN
        pagamento_fev p
            ON p.id_propose = omie.sk_propose
            AND DATE_TRUNC('month',p.dt_due) = DATE_TRUNC('month',omie.dt_register)
            AND CAST(p.value AS DECIMAL(15,2)) = CAST(omie.due_amount AS DECIMAL(15,2))
),
final_agreements AS (
    WITH transaction_entries AS (
        SELECT *
        FROM
            base_omie te
        WHERE
            te.provisional_group IN ('Assinatura','Taxa de Ativação','Taxa de ativação', 'Garantia','Rescisão')
            AND te.open_amount > 0
            AND te.sk_propose IS NOT NULL
            AND te.dt_due < now()
            AND te.dt_register < DATE('2023-07-01')
            AND te.sk_transaction NOT IN (SELECT sk_transaction FROM omie_asaas_match)
    ),
    agreements AS (
        SELECT
            apl.id_propose,
            MIN(apl.dt_confirmed_payment) AS min_dt_paid,
            CAST(SUM(apl.value - IF(apl.fine_value IS NULL, 0, apl.fine_value) - IF(apl.interest_value IS NULL, 0, apl.interest_value)) AS DECIMAL(15,2)) AS agreement_amount
        FROM
            datalake_rental_guarantee_platform_clean.agreement_payment_legacy apl
        WHERE
            apl.status = 'RECEIVED'
            AND MONTH(apl.dt_confirmed_payment) >= 2
        GROUP BY 1
    )
   ,transaction_entries_agreement AS (
        SELECT
            te.*,
            a.min_dt_paid,
            a.agreement_amount,
            SUM(open_amount) OVER (PARTITION BY te.sk_propose ORDER BY provisional_group DESC, dt_register ASC, sk_transaction_entry DESC)  AS cumulative_open_amount,
            ROW_NUMBER() OVER (PARTITION BY te.sk_propose ORDER BY provisional_group DESC, dt_register ASC, sk_transaction_entry DESC) AS rn
        FROM
            transaction_entries te
        LEFT JOIN
            agreements a
                ON te.sk_propose = a.id_propose
    )
   ,cumulative_logic_amounts AS (
        SELECT
            *,
            agreement_amount - cumulative_open_amount AS cumulative_agreement_amount
        FROM
            transaction_entries_agreement
        WHERE
            agreement_amount IS NOT NULL
    )
    SELECT
        *,
        CASE
            WHEN cumulative_agreement_amount > 0 THEN open_amount
            WHEN cumulative_agreement_amount < 0 AND open_amount >= -1*cumulative_agreement_amount THEN (open_amount + cumulative_agreement_amount)
            WHEN cumulative_agreement_amount < 0 AND open_amount < -1*cumulative_agreement_amount THEN 0
        END AS paid_amount_agreement
    FROM
        cumulative_logic_amounts
),
omie_pgto_acordos AS (
    WITH aux AS (
        SELECT DISTINCT
            sk_propose,
            sk_transaction,
            client_cpf_cnpj,
            dt_register,
            dt_due,
            CASE WHEN paid_amount_agreement>0 THEN min_dt_paid ELSE dt_paid END AS dt_paid,
            due_amount,
            paid_amount_agreement,
            (paid_amount+paid_amount_agreement) AS paid_amount,
            (due_amount-(paid_amount+paid_amount_agreement)) AS open_amount,
            discount_value,
            description AS bill_item,
            provisional_group,
            is_danos_imovel,
            CAST('false' AS BOOLEAN) AS is_delinquency_renovacao,
            CAST('false' AS BOOLEAN) AS is_perdao_divida
        FROM
            final_agreements
    )
    SELECT
        "c_omie" AS origin_table_aux,
        "omie" AS origin_table,
        aux.sk_propose,
        CAST(NULL AS INT) AS sk_propose_20,
        sk_transaction,
        sk_transaction AS sk_key,
        client_cpf_cnpj,
        dt_register,
        dt_due,
        dt_paid,
        dt_paid AS dt_paid_aux,
        IF(DATE_DIFF(COALESCE(dt_paid,current_date), dt_due)<0,0,DATE_DIFF(COALESCE(dt_paid,current_date), dt_due)) AS dias_atraso,
        due_amount,
        paid_amount,
        open_amount,
        discount_value,
        bill_item,
        provisional_group,
        is_danos_imovel,
        IF(p.is_contract AND p.dt_ended IS NULL, true, false) AS is_contract_active,
        p.dt_contract_started,
        p.dt_ended_official dt_contract_ended,
        vp.total_package_amount valor_pacote,
        CAST('false' AS BOOLEAN) AS is_delinquency_renovacao,
        CAST('false' AS BOOLEAN) AS is_perdao_divida
    FROM
        aux
    LEFT JOIN
        dw_velo.fact_velo_propose p
            ON aux.sk_propose = p.sk_propose
    LEFT JOIN
        dw_velo.dim_velo_propose_values vp
            ON p.sk_propose_values = vp.sk_propose_values
    WHERE
        paid_amount > 0
),
omie_assinatura AS (
    SELECT *
    FROM
        base_omie_ifrs
    WHERE
        provisional_group IN ('Assinatura', 'Taxa de ativação')
        AND open_amount <= 0

    UNION

    SELECT * FROM omie_asaas_match

    UNION

    SELECT *
    FROM
        omie_pgto_acordos
    WHERE
        provisional_group IN ('Assinatura', 'Taxa de ativação')
),
base_sap_ifrs AS (
    WITH omie AS (
        SELECT DISTINCT
            sk_propose,
            oc.client_cpf_cnpj
        FROM
            dw_velo.fact_velo_transaction_entries AS te
        LEFT JOIN
            dw_velo.dim_velo_transaction AS t
                ON t. sk_transaction = te.sk_transaction
        INNER JOIN
            dw_velo.dim_velo_transaction_category AS c
                ON te.sk_category = c.sk_category
        LEFT JOIN
            dw_velo.dim_velo_omie_client AS oc
                ON oc.sk_client = te.sk_omie_client
        WHERE
            transaction_type = 'CONTA_A_RECEBER'
    )
    ,sap AS (
        SELECT
            id_business_entity AS sk_propose,
            id_transaction AS sk_transaction,
            CASE
                WHEN p.is_contract AND p.dt_ended IS NULL THEN true
                ELSE false
            END AS is_contract_active,
            p.dt_contract_started,
            p.dt_ended_official AS dt_contract_ended,
            vp.total_package_amount AS valor_pacote,
            CASE
                WHEN (accounting_rule LIKE 'velo:a.01%'
                    OR accounting_rule LIKE 'velo:at%'
                    OR accounting_rule LIKE 'velo:f.01%'
                    OR accounting_rule LIKE 'velo:ar.01%'
                    OR accounting_rule LIKE 'velo:ac.01%'
                    OR accounting_rule LIKE 'velo:AS.01%'
                    OR accounting_rule LIKE 'velo:bk.01%' )
                THEN 'ASSINATURA'
                WHEN
                    accounting_rule LIKE 'velo:am.01%'
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
            SUM(debit_credit) valor_pago
        FROM
            datalake_accounting_funnel.ledger sap
        LEFT JOIN
            dw_velo.fact_velo_propose p
                ON p.sk_propose = sap.id_business_entity
        LEFT JOIN
            dw_velo.dim_velo_propose_values vp
                ON p.sk_propose_values = vp.sk_propose_values
        WHERE
            dt_reference between DATE('2023-09-01') AND DATE('2023-09-30')
            AND credit = 0
            AND account_name IN ('Títulos recebidos via cartão de crédito', 'Itaú Ag. 8792 Conta 49458-8')

        GROUP BY 1,2,3,4,5,6,7,8,9
    )
    SELECT DISTINCT
        "d_sap" AS origin_table_aux,
        "sap" AS origin_table,
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
    FROM
        sap
    JOIN
        omie
            ON omie.sk_propose = sap.sk_propose
    WHERE
        accounting_rule IN ('GARANTIA', 'ASSINATURA')
),

base_payment_asaas_sap AS (
    WITH payment_asaas_sap AS (
        SELECT DISTINCT
            s.id_business_entity AS sk_propose,
            p.id AS sk_transaction,
            s.status AS sent_status,
            p.billing_type,
            DATE(p.ts_created) AS dt_register,
            DATE(p.ts_due) dt_due,
            DATE(s.ts_created) AS dt_paid,
            DATE_DIFF(DATE(s.ts_created),DATE(p.ts_due)) AS dias_atraso,
            p.value AS due_amount,
            p.value AS paid_amount,
            0 AS open_amount,
            0 AS discount_value,
            per.document AS client_cpf_cnpj,
            "Assinatura" AS provisional_group,
            false AS is_danos_imovel,
            CASE WHEN pr.is_contract AND pr.dt_ended IS NULL THEN true ELSE false END AS is_contract_active,
            pr.dt_contract_started,
            pr.dt_ended_official AS dt_contract_ended,
            vp.total_package_amount AS valor_pacote
        FROM
            datalake_rental_guarantee_platform_clean.payment p
        LEFT JOIN
            datalake_rental_guarantee_platform_clean.sap s
                ON s.id_finance_entity = p.id
        LEFT JOIN
            dw_velo.fact_velo_propose	pr
                ON p.id_propose = pr.sk_propose
        LEFT JOIN
            dw_velo.bridge_velo_propose_person ps
                ON p.id_propose = ps.sk_propose
                AND ps.is_primary_person
        LEFT JOIN
            dw_velo.dim_velo_propose_person per
                ON per.sk_person = ps.sk_person
        LEFT JOIN
            dw_velo.dim_velo_propose_values vp
                ON pr.sk_propose_values = vp.sk_propose_values
        WHERE
            (
                s.trigger = 'TRIGGER_ACTIVATION_RECURRENCE_ASAAS'
                OR s.trigger = 'TRIGGER_ACTIVATION_RECURRENCE_ASAAS_CHARGEBACK'
                OR s.trigger = 'TRIGGER_ACTIVATION_RECURRENCE_WITH_FINE_INTEREST_ASAAS'
            )
            AND s.status = 'SUCCESS'
    )
    , rn AS (
        SELECT
        *,
        ROW_NUMBER() OVER(PARTITION BY sk_transaction ORDER BY dt_due) rn
        FROM
            payment_asaas_sap
    )
    SELECT
        "b_payment" AS origin_table_aux,
        "payment" AS origin_table,
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
        "Assinatura" AS bill_item,
        provisional_group,
        is_danos_imovel,
        is_contract_active,
        dt_contract_started,
        dt_contract_ended,
        valor_pacote,
        CAST('false' AS BOOLEAN) AS is_delinquency_renovacao,
        CAST('false' AS BOOLEAN) AS is_perdao_divida
    FROM
        rn
    WHERE
        rn = 1
),
base_assinatura_3_0 AS (
    WITH ajuste_pagamento AS (
        SELECT
            sk_payment,
            IF(status.desc_lvl_1 IN ('SUCCESS','REFUNDED', 'CHARGEBACK'),pay.dt_paid,NULL) AS dt_paid,
            CASE
            WHEN status.desc_lvl_1 IN ('SUCCESS','REFUNDED', 'CHARGEBACK') OR pay.dt_paid IS NOT NULL THEN pay.due_amount
            ELSE 0
            END AS paid_amount
        FROM
            dw_velo.fact_velo_payment pay
        LEFT JOIN
            dw_velo.dim_velo_junk AS status
                ON status.sk_junk = pay.sk_status
        WHERE
            pay.is_occurrence = false
    ),

    casos_reembolso AS (
        SELECT
            DISTINCT pay.sk_payment
        FROM
            dw_velo.fact_velo_payment pay
        LEFT JOIN
            dw_velo.fact_velo_propose	pr
                ON pay.sk_propose = pr.sk_propose
        LEFT JOIN
            dw_velo.dim_velo_junk AS status
                ON status.sk_junk = pay.sk_status
        LEFT JOIN
            dw_velo.dim_velo_junk gateway
                ON gateway.sk_junk = pay.sk_payment_gateway
        LEFT JOIN
            dw_velo.dim_velo_junk billing
                ON billing.sk_junk = pay.sk_billing_type
        WHERE
            pr.dt_ended IS NOT NULL
            AND billing.desc_lvl_1 = 'ANNUAL_CREDIT_CARD'
            AND status.desc_lvl_1 = 'REFUNDED'
    )
    ,base AS (
        SELECT DISTINCT
            pay.sk_propose,
            pay.sk_payment AS sk_transaction,
            ps.is_primary_person,
            per.document AS client_cpf_cnpj,
            pay.dt_created AS dt_register,
            pay.dt_due,
            ajuste_pagamento.dt_paid,
            CASE
                WHEN ajuste_pagamento.dt_paid IS NOT NULL AND DATE_DIFF(ajuste_pagamento.dt_paid,pay.dt_due)<=0 THEN 0
                WHEN pay.is_paid_late THEN DATE_DIFF(ajuste_pagamento.dt_paid,pay.dt_due)
                WHEN ajuste_pagamento.dt_paid IS NULL AND pay.dt_due < current_date THEN DATE_DIFF(current_date,pay.dt_due)
            END AS dias_atraso,
            pay.due_amount,
            ajuste_pagamento.paid_amount AS paid_amount,
            pay.due_amount - ajuste_pagamento.paid_amount AS open_amount,

            0 AS discount_value,
            "Assinatura" AS provisional_group,
            false AS is_danos_imovel,
            IF(pr.is_contract AND pr.dt_ended IS NULL,true,false) AS is_contract_active,
            pr.dt_contract_started,
            pr.dt_ended_official AS dt_contract_ended,
            vp.total_package_amount AS valor_pacote,
            gateway.desc_lvl_1 AS gateway,
            status.desc_lvl_1 AS status_payment
        FROM
            dw_velo.fact_velo_payment pay
        LEFT JOIN
            ajuste_pagamento
                ON ajuste_pagamento.sk_payment = pay.sk_payment
        LEFT JOIN
            dw_velo.fact_velo_propose	pr
                ON pay.sk_propose = pr.sk_propose
        LEFT JOIN
            dw_velo.bridge_velo_propose_person ps
                ON pay.sk_propose = ps.sk_propose AND ps.is_primary_person
        LEFT JOIN
            dw_velo.dim_velo_propose_person per
                ON per.sk_person = ps.sk_person
        LEFT JOIN
            dw_velo.dim_velo_propose_values vp
                ON pr.sk_propose_values = vp.sk_propose_values
        LEFT JOIN
            dw_velo.dim_velo_junk AS status
                ON status.sk_junk = pay.sk_status
        LEFT JOIN
            dw_velo.dim_velo_junk gateway
                ON gateway.sk_junk = pay.sk_payment_gateway
        LEFT JOIN
            dw_velo.dim_velo_junk billing
                ON billing.sk_junk = pay.sk_billing_type
        LEFT JOIN
            casos_reembolso cr
                ON cr.sk_payment = pay.sk_payment
        WHERE
            pay.is_occurrence = false
            AND pay.is_legacy = false
            AND gateway.desc_lvl_1 != 'ASAAS'


            AND status.desc_lvl_1 = 'SUCCESS'
            AND pr.dt_contract_started IS NOT NULL
            AND cr.sk_payment IS NULL
    )
    , rn AS (
        SELECT
        *,
        ROW_NUMBER() OVER(PARTITION BY sk_transaction ORDER BY dt_due) rn
        FROM base
    )
    SELECT
        "b_payment" AS origin_table_aux,
        "payment" AS origin_table,
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
        "Assinatura" AS bill_item,
        provisional_group,
        is_danos_imovel,
        is_contract_active,
        dt_contract_started,
        dt_contract_ended,
        valor_pacote,
        CAST('false' AS BOOLEAN) AS is_delinquency_renovacao,
        CAST('false' AS BOOLEAN) AS is_perdao_divida
    FROM
        rn
    WHERE
        rn = 1
),
base_inadimplecia_assinatura AS (
    WITH cpf_cnpj_person AS (
        SELECT
            sk_propose,
            document,
            ROW_NUMBER() OVER(PARTITION BY sk_propose ORDER BY document) rn
        FROM
            dw_velo.bridge_velo_propose_person ps
        LEFT JOIN
            dw_velo.dim_velo_propose_person per
                ON per.sk_person = ps.sk_person
        WHERE
            ps.is_primary_person
    )

    ,delinquency_entry AS (
        SELECT
        d.id AS id_delinquency,
        entry.id AS id_delinquency_entry,
        entry.bill_item,
        entry.value AS entry_value,
        CASE
            WHEN d.amount_paid - d.original_value >= 0 THEN entry.value
            WHEN d.amount_paid>0 THEN (entry.value/d.original_value)*d.amount_paid
        END AS paid_amount_entry
    FROM
        datalake_rental_guarantee_platform_clean.delinquency d
    LEFT JOIN
        datalake_rental_guarantee_platform_clean.delinquency_entry entry
            ON d.id = entry.id_delinquency
    WHERE
        is_active = true

        AND id_type IN (1,2)
    )

    SELECT DISTINCT
        d.id_propose AS sk_propose,
        d.id AS sk_delinquency,
        entry.id_delinquency_entry AS sk_delinquency_entry,
        d.id_status,
        d.id_type,
        doc.document AS client_cpf_cnpj,
        DATE_TRUNC('day',d.ts_created) AS dt_register,
        d.dt_due,
        d.dt_paid,
        IF(d.id_status=7, d.dt_due, d.dt_paid) AS dt_paid_aux,
        DATE_DIFF(COALESCE(d.dt_paid,current_date),d.dt_due) AS dias_atraso,

        d.original_value AS due_amount_delinquency,
        d.amount_paid AS paid_amount_delinquency,
        IF(d.id_status IN (3,7) OR d.original_value - d.amount_paid < 0, 0, d.original_value - d.amount_paid) AS net_amount_delinquency,
        IF(d.id_status IN (3,7) AND amount_paid < original_value, original_value - amount_paid, NULL) AS discount_value_delinquency,

        IF(d.id_type IN (0,4,5,6), d.original_value, entry.entry_value) AS due_amount_entry,
        IF(d.id_type IN (0,4,5,6), d.amount_paid, entry.paid_amount_entry) AS paid_amount_entry,
        CASE
            WHEN d.id_status IN (3,7) OR d.original_value - d.amount_paid < 0 THEN 0
            WHEN d.id_type IN (0,4,5,6) THEN d.original_value - d.amount_paid
            ELSE (entry.entry_value - COALESCE(entry.paid_amount_entry,0 ))
        END AS net_amount_entry,
        CASE
            WHEN d.id_status IN (3,7) AND d.id_type IN (0,4,5,6) AND amount_paid < original_value THEN abs(original_value - amount_paid)
            WHEN d.id_status IN (3,7) AND COALESCE(entry.paid_amount_entry,0) < entry.entry_value THEN abs(entry.entry_value - COALESCE(entry.paid_amount_entry,0))
        END AS discount_value_entry,
        CASE
            WHEN id_type IN (0,4,5,6) THEN 'Assinatura'
            WHEN id_type = 1 THEN 'Garantia'
            WHEN id_type = 2 THEN 'Rescisão'
        END AS provisional_group,
        IF(id_type = 4, true, false) AS is_delinquency_renovacao,
        IF(d.id_status = 7, true, false) AS is_perdao_divida,
        entry.bill_item,
        IF(entry.bill_item = 'REALTY_DAMAGE', true, false) AS is_danos_imovel,
        IF(p.is_contract AND p.dt_ended IS NULL, true, false) AS is_contract_active,
        p.dt_contract_started,
        p.dt_ended_official AS dt_contract_ended,
        vp.total_package_amount AS valor_pacote
    FROM
        datalake_rental_guarantee_platform_clean.delinquency d
    LEFT JOIN
        delinquency_entry entry
            ON d.id = entry.id_delinquency
    LEFT JOIN
        datalake_rental_guarantee_platform_clean.delinquency_has_agreement da
            ON d.id = da.id_delinquency
    LEFT JOIN
        datalake_rental_guarantee_platform_clean.agreement a
            ON da.id_agreement = a.id
    LEFT JOIN
        datalake_rental_guarantee_platform_clean.agreement_payment ap
            ON ap.id_agreement = a.id
    LEFT JOIN
        cpf_cnpj_person doc
            ON doc.sk_propose = d.id_propose AND rn = 1
    LEFT JOIN
        dw_velo.fact_velo_propose	p
            ON d.id_propose = p.sk_propose
    LEFT JOIN
        dw_velo.dim_velo_propose_values vp
            ON p.sk_propose_values = vp.sk_propose_values
    WHERE
        is_active = true
),
base_inadimplecia_ifrs_assinatura AS (
    SELECT DISTINCT
        "a_delinquency" AS origin_table_aux,
        "delinquency" AS origin_table,
        sk_propose,
        CAST(NULL AS INT) AS sk_propose_20,
        COALESCE(sk_delinquency_entry, sk_delinquency)sk_transaction,
        sk_delinquency AS sk_key,
        client_cpf_cnpj,
        dt_register,
        dt_due,
        dt_paid,
        dt_paid_aux,
        dias_atraso,
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
    FROM
        base_inadimplecia_assinatura
),

base_assinatura_ifrs_sem_repasse AS (
    WITH
    base_unificada AS (
        SELECT *
        FROM
            omie_assinatura
        WHERE
            provisional_group IN ('Assinatura','Taxa de Ativação','Taxa de ativação')

        UNION

        SELECT *
        FROM
            base_sap_ifrs
        WHERE
            provisional_group IN ('ASSINATURA')

        UNION

        SELECT * FROM base_payment_asaas_sap


        UNION

        SELECT *
        FROM
            base_assinatura_3_0

        UNION

        SELECT *
        FROM
            base_inadimplecia_ifrs_assinatura
        WHERE
            provisional_group IN ('Assinatura')
    )
    , deduplicao AS (
        SELECT
            *,
            ROW_NUMBER() OVER (PARTITION BY sk_propose, DATE_TRUNC('month',DATE(dt_due)), due_amount ORDER BY open_amount ASC, dt_paid_aux DESC, origin_table_aux ASC) AS rn
        FROM
            base_unificada
    )
    SELECT
        origin_table,
        sk_propose,
        sk_propose_20,
        sk_transaction,
        sk_key,
        client_cpf_cnpj,
        dt_register,
        dt_due,
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
    FROM
        deduplicao
    WHERE
        rn = 1
),

repasse_direto AS (
    WITH sap AS (
        SELECT
            id_finance_entity AS id_fatura,
            id_finance_entity_entry AS id_contract,
            credit AS mensalidade_por_contrato
        FROM
            datalake_accounting_funnel.ledger
        WHERE
            (
                account_number = '113009'
                OR account_name IN ('Títulos recebidos via cartão de crédito', 'Itaú Ag. 8792 Conta 49458-8')
            )
            AND debit = 0
    )
    ,cpf_cnpj_person AS (
        SELECT
            sk_propose,
            document,
            ROW_NUMBER() OVER(PARTITION BY sk_propose ORDER BY document) rn
        FROM
            dw_velo.bridge_velo_propose_person ps
        LEFT JOIN
            dw_velo.dim_velo_propose_person per
                ON per.sk_person = ps.sk_person
        WHERE
            ps.is_primary_person
    )
    ,recebimento_por_contrato_boleto_billing AS (
        SELECT DISTINCT
            c.uuid_company AS imob_uuid,
            imob.broker_name,
            c.id AS imob_id,
            i.id AS fatura_id,
            i.status AS fatura_status,
            DATE(i.ts_created) AS dt_criacao_invoice,
            ADD_MONTHS(DATE(CONCAT(CAST(i.accrual_year AS VARCHAR(10)),'-',CAST((i.accrual_month) AS VARCHAR(10)),'-','01')),1 ) AS dt_ref_boleto,
            i.dt_due AS fatura_vencimento,
            i.total_amount AS fatura_valor,
            COALESCE(sap.id_contract,e.propose) AS sk_propose,
            COALESCE(sap.mensalidade_por_contrato,e.amount) AS mensalidade_por_contrato,
            IF(b.status IN ('PAID','PAID_AFTER_DUE_DATE'), mensalidade_por_contrato, 0) AS paid_amount,
            DATE(b.ts_paid) AS boleto_compensando_em,
            DATE(b.ts_created) AS dt_boleto_created,
            b.status AS boleto_status,
            doc.document AS client_cpf_cnpj,
            fp.dt_contract_started,
            fp.dt_ended_official AS dt_contract_ended,
            IF(fp.is_contract AND fp.dt_ended IS NULL, true, false) AS is_contract_active,
            vp.total_package_amount AS valor_pacote,
            ROW_NUMBER() OVER (PARTITION BY sap.id_contract,ADD_MONTHS(DATE(CONCAT(CAST(i.accrual_year AS VARCHAR(10)),'-',CAST((i.accrual_month) AS VARCHAR(10)),'-','01')),1 ) ORDER BY DATE(b.ts_paid) DESC, DATE(b.ts_created) DESC) AS rn
        FROM
            datalake_rental_guarantee_platform_clean.billing_report i
        LEFT JOIN
            datalake_rental_guarantee_platform_clean.bill b
                ON b.id = i.id_bill
        LEFT JOIN
            datalake_rental_guarantee_platform_clean.entry e
                ON e.id_billing_report = i.id
        LEFT JOIN
            datalake_rental_guarantee_platform_clean.company c
                ON c.id = i.id_company
        LEFT JOIN
            dw_velo.dim_velo_broker imob
                ON imob.sk_broker = c.id
        LEFT JOIN
            dw_velo.fact_velo_propose fp
                ON fp.sk_propose = e.propose
        LEFT JOIN
            sap
                ON sap.id_fatura = CAST(i.id AS VARCHAR(10))
                AND sap.id_contract  = CAST(fp.sk_propose AS VARCHAR(10))
        LEFT JOIN
            dw_velo.dim_velo_propose_values vp
                ON fp.sk_propose_values = vp.sk_propose_values
        LEFT JOIN
            cpf_cnpj_person doc
                ON doc.sk_propose = fp.sk_propose AND rn = 1
        -- WHERE
        --     b.status NOT IN ('WRITTEN_DOWN')
        --     AND CONCAT(b.status,i.status) NOT IN ('OVERDUECANCELED')
    )
    SELECT
        'invoice' AS origin_table,
        sk_propose,
        CAST(NULL AS INT) AS sk_propose_20,
        CONCAT(sk_propose,REPLACE(dt_ref_boleto,'-','')) AS sk_transaction,
        CONCAT(sk_propose,fatura_id) AS sk_key,
        client_cpf_cnpj,
        dt_ref_boleto AS dt_register,
        dt_ref_boleto AS dt_due,
        boleto_compensando_em AS dt_paid,
        IF( DATE_DIFF(COALESCE(boleto_compensando_em,current_date),fatura_vencimento)<0, 0, DATE_DIFF(COALESCE(boleto_compensando_em,current_date),fatura_vencimento) ) AS dias_de_atraso,
        mensalidade_por_contrato AS due_amount,
        paid_amount,
        (mensalidade_por_contrato -  paid_amount) AS open_amount,
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
    FROM
        recebimento_por_contrato_boleto_billing
    WHERE
        rn = 1
),
base_final_unificada AS (

    WITH
    unificada AS (
        SELECT * FROM base_assinatura_ifrs_sem_repasse

        UNION

        SELECT * FROM repasse_direto
    )
    ,unificada_aux AS (
        SELECT
            *,
            ROW_NUMBER() OVER (PARTITION BY sk_propose,DATE_TRUNC('month',DATE(dt_due)),round(due_amount) ORDER BY open_amount ASC, dt_paid DESC) rn
        FROM
            unificada
    )
    SELECT
        origin_table,
        sk_propose,
        sk_propose_20,
        sk_transaction,
        sk_key,
        client_cpf_cnpj,
        dt_register,
        dt_due,
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
    FROM
        unificada_aux
    WHERE
        rn = 1
)
SELECT
    origin_table,
    sk_propose,
    sk_propose_20,
    sk_transaction,
    sk_key,
    client_cpf_cnpj,
    dt_register,
    dt_due,
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
FROM
    base_final_unificada
WHERE
    sk_propose IS NOT NULL
