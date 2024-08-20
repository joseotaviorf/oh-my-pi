WITH _dh AS (
    (
        SELECT
            NULL AS document_entry,
            je.accrual_year_month,
            je.dt_created,
            NULL AS dt_document,
            je.dt_due,
            je.dt_reference,
            je.dt_tax,
            je.dt_updated,
            je.id_business_entity,
            NULL AS id_document,
            je.id_external_payment,
            je.id_financial_entity,
            je.id_transaction,
            je.id_user_sign,
            je.legacy_uuid_rsd AS legacy_uuid,
            je.total_loc AS loc_total,
            je.memo,
            je.series,
            je.source_client,
            je.source_document_number,
            je.transaction_type,
            je.updated_by,
            je.uuid_rsd AS uuid
        FROM
            datalake_pas.journal_entries je
    )
    UNION ALL
    (
        SELECT
            iin.document_entry AS document_entry,
            iin.accrual_year_month,
            iin.dt_created,
            iin.dt_document,
            iin.dt_due,
            iin.dt_reference,
            iin.dt_tax,
            iin.dt_updated,
            iin.id_business_entity,
            iin.id_document,
            iin.id_external_payment,
            iin.id_financial_entity,
            iin.id_transaction,
            iin.id_user_sign,
            iin.legacy_uuid,
            iin.loc_total,
            iin.memo,
            iin.series,
            iin.source_client,
            iin.source_document_number,
            iin.transaction_type,
            iin.updated_by,
            iin.uuid
        FROM
            datalake_pas.invoices iin
    )
    UNION ALL
    (
        SELECT
            ip.document_entry,
            ip.accrual_year_month,
            ip.dt_created,
            ip.dt_document,
            ip.dt_due,
            ip.dt_reference,
            ip.dt_tax,
            ip.dt_updated,
            ip.id_business_entity,
            NULL AS id_document,
            ip.id_external_payment,
            ip.id_financial_entity,
            ip.id_transaction,
            ip.id_user_sign,
            ip.legacy_uuid,
            ip.loc_total,
            ip.memo,
            ip.series,
            ip.source_client,
            ip.source_document_number,
            ip.transaction_type,
            ip.updated_by,
            ip.uuid
        FROM
            datalake_pas.incoming_payments ip
    )
),
dh AS (
    SELECT
        _dh.id_transaction,
        _dh.id_business_entity,
        _dh.id_external_payment,
        _dh.id_financial_entity,
        _dh.id_user_sign,
        CASE
            _dh.transaction_type
            WHEN '-2' THEN 'OB'
            WHEN '-3' THEN 'BC'
            WHEN '30' THEN 'JE'
            WHEN '15' THEN 'DN'
            WHEN '16' THEN 'RE'
            WHEN '13' THEN 'IN'
            WHEN '203' THEN 'DT'
            WHEN '14' THEN 'CN'
            WHEN '20' THEN 'PD'
            WHEN '21' THEN 'PR'
            WHEN '18' THEN 'PU'
            WHEN '19' THEN 'PU'
            WHEN '204' THEN 'DT'
            WHEN '46' THEN 'PS'
            WHEN '24' THEN 'RC'
            WHEN '1470000049' THEN 'AC'
            WHEN '1470000071' THEN 'DR'
            WHEN '1470000094' THEN 'RT'
            WHEN '-4' THEN 'BN'
            WHEN '321' THEN 'JR'
            ELSE _dh.transaction_type
        END AS transaction_type,
        _dh.memo,
        _dh.source_document_number,
        CASE
            _dh.series
            WHEN 17 THEN 'Primário'
            ELSE CAST(_dh.series AS STRING)
        END AS series,
        _dh.source_client,
        _dh.updated_by,
        _dh.dt_reference,
        _dh.dt_tax,
        _dh.dt_due,
        _dh.accrual_year_month,
        _dh.dt_created,
        _dh.dt_updated,
        _dh.legacy_uuid,
        _dh.uuid,
        _dh.document_entry,
        _dh.loc_total,
        _dh.dt_document,
        _dh.id_document
    FROM
        _dh
),
db AS (
    (
        SELECT
            je.id_transaction,
            je.id_line,
            je.id_business_entity,
            je.id_finance_entity_entry,
            je.id_finance_entity,
            je.id_branch,
            je.cost_center_code,
            je.contra_act,
            je.location_profit_code,
            je.managerial_code,
            je.memo_line,
            je.source_document_number,
            je.series,
            je.account,
            je.account_shortname,
            je.accounting_rule,
            je.accounting_type,
            je.user_type,
            je.transaction_type,
            je.credit,
            je.debit,
            je.accrual_year_month,
            je.dt_due,
            je.dt_reference,
            je.dt_tax,
            NULL AS id_document
        FROM
            datalake_pas.journal_entry_lines je
        WHERE
            je.id_transaction NOT IN ('13', '24')
    )
    UNION ALL
    (
        SELECT
            iin.id_transaction,
            iin.id_line,
            iin.id_business_entity,
            iin.id_finance_entity_entry,
            iin.id_finance_entity,
            iin.id_branch,
            iin.cost_center_code,
            iin.contra_act,
            iin.location_profit_code,
            iin.managerial_code,
            iin.memo_line,
            iin.source_document_number,
            iin.series,
            iin.account,
            iin.account_shortname,
            iin.accounting_rule,
            iin.accounting_type,
            iin.user_type,
            iin.transaction_type,
            iin.credit,
            iin.debit,
            iin.accrual_year_month,
            iin.dt_due,
            iin.dt_reference,
            iin.dt_tax,
            iin.id_document
        FROM
            datalake_pas.invoice_lines iin
    )
    UNION ALL
    (
        SELECT
            ip.id_transaction,
            ip.id_line,
            ip.id_business_entity,
            ip.id_finance_entity_entry,
            ip.id_finance_entity,
            ip.id_branch,
            ip.cost_center_code,
            ip.contra_act,
            ip.location_profit_code,
            ip.managerial_code,
            ip.memo_line,
            ip.source_document_number,
            ip.series,
            ip.account,
            ip.account_shortname,
            ip.accounting_rule,
            ip.accounting_type,
            ip.user_type,
            ip.transaction_type,
            ip.credit,
            ip.debit,
            ip.accrual_year_month,
            ip.dt_due,
            ip.dt_reference,
            ip.dt_tax,
            ip.id_document
        FROM
            datalake_pas.incoming_payments_lines ip
    )
)
SELECT
    dh.id_transaction,
    db.id_business_entity,
    db.id_finance_entity,
    db.id_finance_entity_entry,
    dh.id_external_payment,
    db.id_document,
    db.id_branch,
    CASE
        SUBSTR(db.account, 1, 1)
        WHEN '1' THEN 'Ativo'
        WHEN '2' THEN 'Passivo'
        WHEN '3' THEN 'Receita'
        WHEN '4' THEN 'Despesa'
        WHEN '5' THEN 'Custo'
        WHEN '6' THEN 'Transitória'
        ELSE NULL
    END AS account_type,
    db.account AS account_number,
    coa.name AS account_name,
    dh.series AS series,
    dh.transaction_type || ' ' || dh.source_document_number AS document_number,
    db.accounting_rule,
    db.accounting_type,
    db.user_type,
    dh.source_client,
    COALESCE(dh.memo, db.memo_line) AS comments,
    (db.debit - db.credit) AS debit_credit,
    db.debit,
    db.credit,
    u.name AS created_by,
    db.location_profit_code,
    db.cost_center_code,
    dh.uuid,
    dh.dt_reference,
    dh.dt_due,
    dh.dt_tax,
    dh.dt_updated,
    dh.dt_created,
    dh.accrual_year_month
FROM
    dh
INNER JOIN db
    ON db.id_transaction = dh.id_transaction
LEFT JOIN datalake_pas_clean.users u
    ON u.id = dh.id_user_sign
LEFT JOIN datalake_pas_clean.chart_of_accounts coa
    ON coa.id = db.account
