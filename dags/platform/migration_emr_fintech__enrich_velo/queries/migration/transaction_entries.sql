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
),
client_cpf AS(
    SELECT
        id_client,
        MAX(NULLIF(REPLACE(REPLACE(REPLACE(REGEXP_EXTRACT(client_cpf_cnpj, '(\\d{{3}}\\.\\d{{3}}\.\\d{{3}}\\-\\d{{2}})|(\\d{{3}}\\.\\d{{3}}\\.\\d{{3}}\\,\\d{{2}})|(\\d{{11}})',0),'-',''),'.',''),',',''), '')) AS document_number
    FROM
        datalake_velo_omie.cash_flows
    WHERE
        id_group = 'CONTA_A_RECEBER'
    GROUP BY
        1
),
client_cnpj AS (
    SELECT
        id_client,
        MAX(NULLIF(REPLACE(REPLACE(REPLACE(REGEXP_EXTRACT(client_cpf_cnpj, '(\\d{{2}}\\.\\d{{3}}\\.\\d{{3}}\\/\\d{{4}}\\-\\d{{2}})',0),'-',''),'.',''),'/',''), '')) AS document_number
    FROM
        datalake_velo_omie.cash_flows
    WHERE
        id_group = 'CONTA_A_RECEBER'
    GROUP BY
        1
),
propose_person AS (
    SELECT
        pp_doc.*,
        p_doc.dt_contract_started,
        p_doc.dt_ended
    FROM
        datalake_velo.propose_person AS pp_doc
    LEFT JOIN
        datalake_velo.propose AS p_doc
            ON p_doc.id_propose = pp_doc.id_propose
    WHERE
        pp_doc.id_propose IS NOT NULL
        AND p_doc.id_propose IS NOT NULL
        AND p_doc.is_contract IS TRUE


    UNION ALL

    SELECT
        pp_doc.*,
        p_doc.dt_contract_started,
        p_doc.dt_ended
    FROM
        datalake_velo.propose_person_legacy AS pp_doc
    LEFT JOIN
        datalake_velo.propose_legacy AS p_doc
            ON p_doc.id_propose = pp_doc.id_propose
    WHERE
        pp_doc.id_propose IS NOT NULL
        AND p_doc.id_propose IS NOT NULL
        AND p_doc.is_contract IS TRUE

),
propose_company AS (
    SELECT
        -- pc_doc.*,
        pc_doc.id_company,
        pc_doc.cnpj,
        p_doc.id_propose,
        p_doc.dt_contract_started,
        p_doc.dt_ended
    FROM
        datalake_velo.propose_company AS pc_doc
    LEFT JOIN
        datalake_velo.propose AS p_doc
            ON p_doc.id_propose_company = pc_doc.id_company
    WHERE
        p_doc.id_propose IS NOT NULL
        AND p_doc.is_contract IS TRUE


    UNION ALL

    SELECT
        pc_doc.id_company,
        cc.document AS cnpj,
        p_doc.id_propose,
        p_doc.dt_contract_started,
        p_doc.dt_ended
    FROM
        datalake_rental_guarantee_platform_clean.fiancavelo_proposecompany_legacy AS pc_doc
    LEFT JOIN
        datalake_velo.propose_legacy AS p_doc
            ON p_doc.id_propose_company = pc_doc.id_company
    LEFT JOIN
        datalake_velo_clean.clientes_company AS cc
            ON cc.id = pc_doc.id_company
),
cash_flow_propose AS (
    SELECT DISTINCT
        cf.id_securities,
        COALESCE(pp_doc.id_propose, pp_doc_fallback.id_propose, pc_doc.id_propose, pc_doc_fallback.id_propose) AS id_propose,
        ROW_NUMBER() OVER (PARTITION BY cf.id_securities, cf.id_client ORDER BY COALESCE(pp_doc.id_propose, pp_doc_fallback.id_propose, pc_doc.id_propose, pc_doc_fallback.id_propose) DESC) AS rn
    FROM
        datalake_velo_omie.cash_flows AS cf
    LEFT JOIN
        client_cpf AS ccpf
            ON ccpf.id_client = cf.id_client
    LEFT JOIN
        client_cnpj AS ccnpj
            ON ccnpj.id_client = cf.id_client
    LEFT JOIN
        propose_person AS pp_doc
            ON pp_doc.document = ccpf.document_number
            AND COALESCE(cf.dt_due BETWEEN pp_doc.dt_contract_started AND DATE_ADD(pp_doc.dt_ended, 31), 1=1)
    LEFT JOIN
        propose_person AS pp_doc_fallback
            ON pp_doc_fallback.document = ccpf.document_number
    LEFT JOIN
        propose_company AS pc_doc
            ON pc_doc.cnpj = ccnpj.document_number
            AND COALESCE(cf.dt_due BETWEEN pc_doc.dt_contract_started AND DATE_ADD(pc_doc.dt_ended, 31), 1=1)
    LEFT JOIN
        propose_company AS pc_doc_fallback
            ON pc_doc_fallback.cnpj = ccnpj.document_number
    WHERE
        COALESCE(pp_doc.id_propose, pp_doc_fallback.id_propose, pc_doc.id_propose, pc_doc_fallback.id_propose) IS NOT NULL
)
SELECT
    CAST(CONCAT(ct.id_securities, REPLACE(ct.id_category, '.', '')) AS BIGINT) AS id_transaction_entry,
    CAST(CONCAT(ct.id_securities, CASE WHEN ct.transaction_type = 'CONTA_A_RECEBER' THEN '0' ELSE '1' END) AS BIGINT) AS id_transaction,
    ct.id_category,
    cfp.id_propose,
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
LEFT JOIN
    cash_flow_propose AS cfp
        ON cfp.id_securities = ct.id_securities
        AND cfp.rn = 1
