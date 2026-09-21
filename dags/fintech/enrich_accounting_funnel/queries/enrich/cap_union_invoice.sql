WITH recon_ignored_cap AS (
        SELECT DISTINCT
            sk_contract,
            ABS(due_amount) AS due_amount,
            entry_created_date
        FROM (
            SELECT
                sk_contract,
                due_amount,
                entry_created_date
            FROM
                datalake_gsheets_clean.recon_ignored_cap_iptu
            UNION ALL
            SELECT
                sk_contract,
                due_amount,
                entry_created_date
            FROM
                datalake_gsheets_clean.recon_ignored_cap_condominium
            UNION ALL
            SELECT
                sk_contract,
                due_amount,
                entry_created_date
            FROM
                datalake_gsheets_clean.recon_ignored_cap_consumption
        ) AS ignored_cap
    ),
    invoice_all AS (
        SELECT DISTINCT
        id_entry,
        CAST(sk_invoice_reversed_entry AS BIGINT) AS sk_invoice_reversed_entry,
        id_invoice,
        sk_contract,
        version,
        accounting_version,
        is_contract_b2b,
        locale,
        localidade,
        guarantee,
        rental_administrator,
        is_rental_paid_in_advance,
        is_reversed,
        is_write_off,
        bill_item,
        description,
        has_negotiation,
        has_installments,
        purpose,
        invoice_account_type,
        from_account_type,
        to_account_type,
        account_type,
        CASE
            WHEN status IN ('preview', 'not-invoiceable') AND account_type = 'landlord' THEN 'payable'
            WHEN status IN ('preview', 'not-invoiceable') AND account_type = 'tenant' THEN 'receivable'
            ELSE account_classification
        END account_classification,
        status,
        payment_status,
        reason,
        producer,
        closing_mode,
        paid_via,
        due_amount,
        invoice_due_amount,
        invoice_paid_amount,
        accrual_year_month,
        entry_accrual_year_month,
        entry_creation_accrual_year_month,
        entry_created_date,
        invoice_created_date, 
        invoice_due_date,
        invoice_paid_date,
        invoice_canceled_date,
        invoice_reversal_date,
        invoice_write_off_date,
        invoice_paid_date_next_business_day,
        real_invoice_paid_date,
        contract_start,
        contract_annulment,
        ended_before_started,
        contract_status 
        FROM 
        datalake_accounting_funnel.invoice_all 
        WHERE type = 'FullService'
    ),
    invoice AS
    (
        SELECT
        i.id_entry,
        i.id_invoice,
        i.sk_contract,
        i.version,
        i.accounting_version,
        i.is_contract_b2b,
        i.locale,
        i.localidade,
        i.guarantee,
        i.rental_administrator,
        i.is_rental_paid_in_advance,
        i.is_reversed,
        i.is_write_off,
        i.bill_item,
        i.description,
        i.has_negotiation,
        i.has_installments,
        i.purpose,
        i.invoice_account_type,
        i.from_account_type,
        i.to_account_type,
        i.account_type,
        i.account_classification, 
        i.status,
        i.payment_status,
        i.reason,
        i.producer,
        i.closing_mode,
        i.paid_via,
        i.due_amount,
        i.invoice_due_amount,
        i.invoice_paid_amount,
        i.accrual_year_month,
        i.entry_accrual_year_month,
        i.entry_creation_accrual_year_month,
        DATE(i.entry_created_date) as entry_created_date,
        DATE_FORMAT(i.entry_created_date, 'HH:mm:ss') as entry_created_time,
        i.invoice_created_date, 
        i.invoice_due_date,
        i.invoice_paid_date,
        i.invoice_canceled_date,
        i.invoice_reversal_date,
        i.invoice_write_off_date,
        i.invoice_paid_date_next_business_day,
        i.real_invoice_paid_date,
        i.contract_start,
        i.contract_annulment,
        i.ended_before_started,
            NOT(
                i.bill_item IN ('utilities defaulting') 
                OR (i.bill_item IN ('iptu', 'iptu adjustment') AND version IN ('v0', 'v1', 'no info'))
                OR (i.bill_item IN ('repair ongoing'))
                OR (i.bill_item IN ('condominium defaulting'))
                OR (i.bill_item IN ('condominium' , 'condominium usage', 'condominium reserves funds 5A paid', 'condominium 5A paid', 'condominium reserves funds') AND version NOT IN ('v9', 'v10', 'v11'))
            ) AS pp_pays,  
            ROW_NUMBER() OVER(PARTITION BY i.sk_contract, i.accrual_year_month, i.id_invoice, abs(i.due_amount) ORDER BY i.due_amount ASC) AS entry_sort_ascend,
            ROW_NUMBER() OVER(PARTITION BY i.sk_contract, i.accrual_year_month ORDER BY i.id_entry ASC) AS entry_by_accrual_sort_ascend,
            FALSE is_cap,
        i.sk_invoice_reversed_entry,
        i.contract_status
        FROM 
            invoice_all AS i
    ),
    invoice_contract_status AS (
        SELECT 
            DISTINCT
            sk_contract,
            contract_status
        FROM
            invoice AS i
    ),
    cap_template_invoice AS (
        SELECT DISTINCT
            ap.id_entry,
            ap.id_invoice,
            ap.sk_contract,
            ap.version,
            accounting_version,
            ap.is_contract_b2b,
            ap.locale,
            ap.localidade,
            ap.guarantee,
            ap.rental_administrator,
            ap.is_rental_paid_in_advance,
            false as is_reversed,
            false as is_write_off,
            ap.bill_item,
            ap.description,
            ap.has_negotiation,
            ap.has_installments,
            ap.purpose,
            ap.invoice_account_type,
            ap.from_account_type,
            ap.to_account_type,
            ap.account_type,
            ap.account_classification,
            ap.status,
            CAST(NULL AS STRING) AS payment_status,
            CAST(NULL AS STRING) AS reason,
            CAST(NULL AS STRING) AS producer,
            ap.closing_mode,
            'cap' as paid_via,
            ap.due_amount,
            ap.invoice_due_amount,
            ap.invoice_due_amount AS invoice_paid_amount,
            ap.accrual_year_month,
            ap.entry_accrual_year_month,
            ap.entry_creation_accrual_year_month,
            DATE(ap.entry_created_date) as entry_created_date,
            DATE_FORMAT(ap.entry_created_date, 'HH:mm:ss') as entry_created_time,
            ap.invoice_created_date,
            ap.invoice_due_date,
            ap.invoice_paid_date,
            ap.invoice_paid_date_next_business_day,
            ap.invoice_paid_date AS real_invoice_paid_date,
            ap.invoice_canceled_date,
            NULL as invoice_reversal_date,
            NULL as invoice_write_off_date,
            ap.contract_start,
            ap.contract_annulment,
            ap.contract_start > c1.dt_termination AND c1.dt_termination IS NOT NULL AS ended_before_started,
            ap.pp_pays,
            ap.entry_sort_ascend,
            ap.entry_by_accrual_sort_ascend,
            ap.is_cap,
            ap.sk_invoice_reversed_entry,
            i.contract_status
        FROM 
            datalake_accounting_funnel.accounts_payable AS ap
        LEFT JOIN
            invoice_contract_status AS i
                ON i.sk_contract = CASE
                        WHEN ap.sk_contract = -1
                            THEN -2 - PMOD(HASH(ap.description, ap.due_amount, ap.entry_created_date), 4096)
                        ELSE ap.sk_contract
                    END
        LEFT JOIN
            datalake_ebdb_clean.contract AS c1
                ON c1.id = CASE
                        WHEN ap.sk_contract = -1
                            THEN -2 - PMOD(HASH(ap.description, ap.due_amount, ap.entry_created_date), 4096)
                        ELSE ap.sk_contract
                    END
    ),
    invoice_and_cap AS 
    (
        SELECT * FROM invoice
                UNION ALL
        SELECT * FROM cap_template_invoice
    ),
    invoice_classification AS 
    (
        SELECT
            i.*,
                (i.bill_item IN ('brokerage adm partner', 'brokerage adm partner postponed', 'brokerage fee tax ir adm partner'))
                OR (i.bill_item IN ('rental anticipation') AND i.description LIKE '%antecipação do repasse do aluguel%')      
                OR (i.bill_item IN ('brokerage installment fee', 'brokerage loan fidc', 'brokerage fidc', 'postponement', 'rental guarantee fee','rental guarantee fee refund', 'pro guarantor 5A installment', 'pro guarantor 5A installment refund',
                'adm fee adm partner','igpm adm partner adm fee', 'ipca adm partner adm fee', 'adjustment agreement adm partner adm fee', 'repair offboarding', 'payment adjustment','residential protection 5A acquittance', 'repair ongoing',
                'service fee', 'loss', 'property damage fine', 'campaign discount', 'others', 'campaign discount', 'campaign', 'brokerage adm partner postponed', 'brokerage adm partner', 'brokerage estate agent postponed',
                'brokerage estate agent', 'installment lra', 'adm fee tax pcc adm partner', 'lockin', 'brokerage installment'))
            AS only_one_sided,
            
            ((i.bill_item IN ('adm fee adm partner','igpm adm partner adm fee', 'ipca adm partner adm fee', 'adjustment agreement adm partner adm fee')) AND (i.status = 'open') AND (date(i.invoice_due_date) < current_date))
            OR ((i.bill_item IN ('brokerage adm partner', 'brokerage adm partner postponed', 'brokerage fee tax ir adm partner') AND (i.status = 'open') AND (date(i.invoice_due_date) < current_date)))
            OR  ( (i.bill_item IN  ('repair offboarding') ) AND ( (account_classification = 'receivable' AND account_type = 'landlord') OR (account_classification = 'payable' AND account_type = 'tenant') OR ( UPPER(rental_administrator) <> 'QUINTOANDAR') ) )
            AS post_divergence
        FROM
            invoice_and_cap AS i
    )
    SELECT
        i.id_entry,
        i.id_invoice,
        i.sk_contract,
        i.sk_invoice_reversed_entry,
        i.version,
        i.accounting_version,
        i.locale,
        i.localidade,
        i.guarantee,
        i.rental_administrator,
        i.bill_item,
        i.description,
        i.purpose,
        i.invoice_account_type,
        i.from_account_type,
        i.to_account_type,
        i.account_type,
        i.account_classification,
        i.status,
        CASE
            WHEN ignored_cap.sk_contract IS NOT NULL THEN 'ignored-recon'
            ELSE re.status
        END AS entry_status,
        i.payment_status,
        i.reason,
        i.producer,
        re.producer AS entry_producer,
        i.closing_mode,
        i.paid_via,
        i.entry_created_time,
        i.contract_status,
        i.is_contract_b2b,
        i.is_rental_paid_in_advance,
        i.is_reversed,
        i.is_write_off,
        re.is_not_invoicable AS is_not_invoiceable,
        i.has_negotiation,
        i.has_installments,
        i.due_amount,
        i.invoice_due_amount,
        i.invoice_paid_amount,
        i.accrual_year_month,
        i.entry_accrual_year_month,
        i.entry_creation_accrual_year_month,
        i.ended_before_started,
        i.pp_pays,
        i.entry_sort_ascend,
        i.entry_by_accrual_sort_ascend,
        i.is_cap,
        i.only_one_sided,
        i.post_divergence,
        SUM(
            CASE 
                WHEN i.bill_item = 'cap' THEN 1
                ELSE 0
            END
        ) OVER (PARTITION BY i.sk_contract, i.accrual_year_month) > 0 AS has_paid_amount,
        SUM(
            CASE 
                WHEN NOT(i.bill_item = 'cap') THEN 1
                ELSE 0
            END
        ) OVER (PARTITION BY i.sk_contract, i.accrual_year_month) > 0 AS has_receivable_amount,
        i.entry_created_date,
        i.invoice_created_date,
        i.invoice_due_date,
        i.invoice_paid_date,
        i.invoice_canceled_date,
        i.invoice_reversal_date,
        i.invoice_write_off_date,
        i.invoice_paid_date_next_business_day,
        i.real_invoice_paid_date,
        i.contract_start,
        i.contract_annulment,
        re.ts_retsuko_updated
    FROM
        invoice_classification AS i
    LEFT JOIN
        datalake_retsuko_clean.entry AS re
            ON re.id_external = COALESCE(
                    i.id_entry,
                    -2 - PMOD(HASH(i.sk_contract, i.accrual_year_month, i.due_amount, i.description), 4096)
                )
    LEFT JOIN
        recon_ignored_cap AS ignored_cap
            ON i.is_cap = TRUE
            AND i.sk_contract = ignored_cap.sk_contract
            AND ABS(i.due_amount) = ignored_cap.due_amount
            AND i.entry_created_date = ignored_cap.entry_created_date
