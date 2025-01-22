WITH sap_b1 AS (
    SELECT
        id_transaction,
        id_business_entity,
        id_finance_entity,
        id_finance_entity_entry,
        id_external_payment,
        id_document,
        id_branch,
        account_type,
        account_number,
        account_name,
        series,
        contra_act,
        sap_document_number,
        document_number,
        accounting_rule,
        accounting_type,
        transaction_type,
        user_type,
        source_client,
        comments,
        debit_credit,
        debit,
        credit,
        created_by,
        location_profit_code,
        cost_center_code,
        uuid AS hash,
        dt_created,
        dt_reference,
        dt_due,
        dt_tax,
        accrual_year_month
    FROM
        datalake_pas.ledger_new_template
    WHERE
        dt_reference < '2024-01-01'
),
4hana AS (
    SELECT
        id_transaction,
        id_business_entity,
        id_finance_entity,
        id_finance_entity_entry,
        id_external_payment,
        NULL AS id_document,
        id_company AS id_branch,
        -- CASE
        --     SUBSTR(account, 1, 1)
        --     WHEN '1' THEN 'Ativo'
        --     WHEN '2' THEN 'Passivo'
        --     WHEN '3' THEN 'Receita'
        --     WHEN '4' THEN 'Despesa'
        --     WHEN '5' THEN 'Custo'
        --     WHEN '6' THEN 'Transitória'
        --     ELSE NULL
        -- END
        NULL AS account_type,
        account_number,
        account_shortname AS account_name,
        NULL AS series,
        NULL AS contra_act,
        NULL AS sap_document_number,
        -- accounting_type || ' ' || source_document_number AS document_number,
        NULL AS document_number,
        accounting_rule,
        accounting_type,
        CAST(NULL AS STRING) AS transaction_type,
        user_type,
        source_client,
        COALESCE(memo_line, memo, comments) AS comments,
        (IF(indicator = 'Debit', document_amount, 0) - IF(indicator = 'Credit', document_amount, 0)) AS debit_credit,
        IF(indicator = 'Debit', document_amount, 0) AS debit,
        IF(indicator = 'Credit', document_amount, 0) AS credit,
        created_by,
        location_profit_code,
        cost_center_code,
        hash,
        dt_created,
        dt_accrual AS dt_reference,
        NULL AS dt_due,
        dt_tax,
        accrual_year_month
    FROM
        datalake_pas.4hana_journal_entries_bank_account
    WHERE
        dt_accrual >= '2024-01-01'
),
cte_union AS (
    SELECT * FROM sap_b1
    UNION ALL
    SELECT * FROM 4hana
)
SELECT
    id_transaction,
    id_business_entity,
    id_finance_entity,
    id_finance_entity_entry,
    id_external_payment,
    id_document,
    id_branch,
    account_type,
    account_number,
    account_name,
    series,
    contra_act,
    sap_document_number,
    document_number,
    accounting_rule,
    accounting_type,
    transaction_type,
    user_type,
    source_client,
    comments,
    debit_credit,
    CAST(debit AS DOUBLE) AS debit,
    CAST(credit AS DOUBLE) AS credit,
    created_by,
    location_profit_code,
    cost_center_code,
    hash,
    dt_created,
    dt_reference,
    dt_due,
    dt_tax,
    accrual_year_month
FROM
    cte_union
