WITH invoice_all AS (
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
        is_not_invoiceable_inconsiderable,
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
        i.is_not_invoiceable_inconsiderable,
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
            false as is_not_invoiceable_inconsiderable,
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
                ON i.sk_contract = ap.sk_contract
        LEFT JOIN
            datalake_ebdb_clean.contract AS c1
                ON c1.id = ap.sk_contract
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
            CASE
                WHEN (i.bill_item IN ('light water or gas', 'utilities defaulting') OR UPPER(i.description) = 'CONTAS DE CONSUMO CAP') AND i.accounting_version = 'v1' THEN 'Contas de Consumo' 
                WHEN (i.bill_item IN ('iptu', 'iptu adjustment', 'iptu defaulting') OR UPPER(i.description) = 'IPTU CAP') AND i.accounting_version = 'v1' THEN 'IPTU'
                WHEN i.bill_item IN ('repair work', 'improvement work','repair ongoing') AND i.accounting_version = 'v1' THEN 'Reparos Ongoing'
                WHEN i.bill_item IN ('debit negotiation', 'collections negotiation', 'evictions debt relief negotiation', 'evictions costs', 'evictions negotiation', 'evictions lawyers') THEN 'Valores em Negociação'
                WHEN (i.bill_item IN ('condominium fine') AND (from_account_type = 'contract expenses' OR to_account_type = 'contract expenses')) OR (i.bill_item IN ('condominium 5A paid') AND to_account_type IN ('quinto andar') AND (lower(description) like '%orreios%')) THEN 'Multa Condomínio'
                WHEN (
                        i.bill_item IN ('condominium' , 'condominium usage', 'condominium defaulting', 'condominium reserves funds 5A paid', 'condominium reserves funds') 
                    OR 
                        UPPER(i.description) = 'CONDOMÍNIO CAP'
                    OR 
                        (i.bill_item IN ('condominium 5A paid') AND to_account_type NOT IN ('contract expenses', 'quinto andar') )
                    ) 
                    AND i.accounting_version = 'v1' 
                    THEN 'Condomínio'
                WHEN i.bill_item IN ('early termination fee', 'early termination fee non protection') AND i.accounting_version = 'v1' THEN 'Multa Rescisória'
                WHEN i.bill_item IN ('postponement') THEN 'Valores Postergados'
                WHEN i.bill_item IN ('rental guarantee fee', 'pro guarantor 5A installment') AND guarantee = 'RentalGuarantee' AND i.accounting_version = 'v1' THEN 'Garantia a Receber - Garantia 2.0' 
                WHEN i.bill_item IN ('rental guarantee fee refund', 'pro guarantor 5A installment refund') AND guarantee = 'RentalGuarantee' AND i.accounting_version = 'v1' THEN 'Devolução de títulos a receber - Garantia 2.0'
                WHEN i.bill_item IN ('rental guarantee', 'pro guarantor 5A installment') AND guarantee != 'RentalGuarantee' AND i.accounting_version = 'v1' THEN 'Garantia a Receber - Fianças' 
                WHEN i.bill_item IN ('rental guarantee fee refund', 'pro guarantor 5A installment refund') AND guarantee != 'RentalGuarantee' AND i.accounting_version = 'v1' THEN 'Devolução de títulos a receber - Fianças'  
                WHEN i.bill_item IN ('adm fee adm partner','igpm adm partner adm fee', 'ipca adm partner adm fee', 'adjustment agreement adm partner adm fee', 'adm fee tax pcc adm partner') THEN 'Taxa de administração - Imobiliária Parceira'
                WHEN i.bill_item IN ('brokerage adm partner', 'brokerage adm partner postponed', 'brokerage fee tax ir adm partner') AND i.accounting_version = 'v1' THEN 'Taxa de corretagem - Imobiliária Parceira'
                WHEN i.bill_item IN ('repair offboarding') THEN 'Projeto Reparos - Novo Modelo'
                WHEN i.bill_item IN ('payment adjustment') THEN 'Payment Adjustment'   
                WHEN i.bill_item IN ('fine and interest', 'fine', 'negotiation fine') THEN 'Late Payment Fee - Fine'
                WHEN i.bill_item IN ('negotiation fine and interest') THEN 'Late Payment Fee - Negotiation'
                WHEN i.bill_item IN ('interest', 'negotiation interest') THEN 'Late Payment Fee - Interest'
                WHEN i.bill_item IN ('rental anticipation', 'rental anticipation 5A paid') THEN 'Aluguel pago antecipadamente'
                WHEN i.bill_item IN ('rental anticipation fee') THEN 'Receita - Antecipação MRA'
                WHEN i.bill_item IN ('residential protection 5A acquittance', 'residential protection 5A fund transfer') AND i.accounting_version = 'v1' THEN 'Proteção Residencial 5A' 
                WHEN i.bill_item IN ('non protection 5a') AND i.accounting_version = 'v1' THEN 'Não proteção'
                WHEN i.bill_item IN ('property damage fine') THEN 'Multa Danos'
                WHEN i.bill_item IN ('home insurance', 'home insurance claim', 'insurance guarantee') AND i.accounting_version = 'v1' THEN 'Seguro Incêndio'
                WHEN i.bill_item IN ('home insurance', 'home insurance claim', 'insurance guarantee') AND i.accounting_version = 'v2' THEN 'Seguro Incêndio - Novo Modelo'
                WHEN i.bill_item IN ('brokerage installment fee') THEN 'Corretagem Parcelada'
                WHEN i.bill_item IN ('brokerage loan fidc') THEN 'Adiantamentos Mova' 
                WHEN i.bill_item IN ('brokerage fidc') THEN 'Corretagem FIDC a repassar' 
                WHEN i.bill_item IN ('brokerage settlement') AND (i.account_classification = 'v2') THEN 'Corretagem a ser descontada'
                WHEN (
                        (
                        (i.bill_item IN ('igpm rental', 'ipca rental', 'adjustment agreement rental', 'rental', 'loss', 'property damage fine', 'campaign discount', 'campaign', 'others', 'lockin',  'brokerage estate agent', 'brokerage estate agent postponed', 'brokerage adm partner', 'brokerage adm partner postponed', 'installment lra', 'brokerage installment', 'adm fee tax pcc adm partner', 'brokerage fee tax ir adm partner', 'non resident landlord', 'between contracts', 'duplicate refund', 'brokerage third party real estate', 'brokerage third party real estate postponed', 'brokerage partner select', 'brokerage partner select postponed', 'adm fee adm partner', 'adjustment agreement adm partner adm fee', 'ipca adm partner adm fee', 'igpm adm partner adm fee',  'evictions debt relief', 'brokerage compensation', 'adm fee', 'service fee', 'brokerage quinto andar postponed'))
                        ) 
                        AND i.accounting_version = 'v1'
                    )                
                    THEN 'ALUGUEL'
                WHEN (
                        (i.bill_item IN ('igpm rental', 'ipca rental', 'adjustment agreement rental', 'rental', 'loss', 'property damage fine', 'campaign discount', 'campaign', 'others',  'lockin',  'brokerage estate agent', 'brokerage estate agent postponed', 'brokerage adm partner', 'brokerage adm partner postponed', 'installment lra', 'brokerage installment', 'adm fee tax pcc adm partner', 'brokerage fee tax ir adm partner', 'non resident landlord', 'between contracts', 'duplicate refund', 'brokerage third party real estate',  'brokerage third party real estate postponed', 'brokerage partner select', 'brokerage partner select postponed', 'adm fee adm partner', 'adjustment agreement adm partner adm fee', 'ipca adm partner adm fee', 'igpm adm partner adm fee', 'brokerage compensation', 'condominium', 'repair work', 'light water or gas', 'condominium reserves funds', 'condominium reserves funds',  'residential protection 5A fund transfer', 'iptu',  'iptu adjustment',  'early termination fee',  'early termination fee non protection',  'non protection 5a',  'payment adjustment',  'repair ongoing',  'home insurance',  'rental guarantee fee', 'rental guarantee fee refund', 'condominium usage',  'residential protection 5A acquittance', 'repair offboarding',  'utilities defaulting', 'pro guarantor 5A installment', 'iptu defaulting', 'rental anticipation 5A paid',  'condominium reserves funds 5a paid', 'home insurance claim', 'rental guarantee',  'pro guarantor 5A installment') -- 'postponement',  
                        OR
                        (i.bill_item IN ('condominium 5A paid') AND to_account_type NOT IN ('contract expenses', 'quinto andar'))
                        )
                        AND 
                        (i.accounting_version = 'v2') 
                    )
                THEN 'ALUGUEL - Novo Modelo'
                ELSE 'Outro'
            END AS conta_contabil,

            CASE  
                WHEN i.bill_item IN ('brokerage adm partner postponed', 'brokerage adm partner', 'brokerage estate agent postponed', 'brokerage estate agent', 'property damage fine') THEN 'ALUGUEL'
                WHEN i.bill_item IN ('home insurance', 'home insurance claim') AND (i.accounting_version = 'v2') THEN 'ALUGUEL - Novo Modelo'
                WHEN ( i.bill_item IN ('brokerage installment') OR (i.bill_item IN ('brokerage quinto andar') AND i.description ILIKE '%Crédito - Parcelamento corretagem%') ) THEN 'Corretagem a ser descontada'
                WHEN i.bill_item IN ('condominium 5A paid', 'condominium fine', 'condominium usage', 'repair ongoing', 'residential protection 5A acquittance', 'utilities defaulting', 'iptu defaulting', 'evictions costs') AND  (i.accounting_version = 'v2') THEN 'Valores pagos antecipados - Novo modelo'
            END AS conta_contabil_secundaria,

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
        i.payment_status,
        i.reason,
        i.producer,
        i.closing_mode,
        i.paid_via,
        i.entry_created_time,
        i.contract_status,
        i.conta_contabil,
        i.conta_contabil_secundaria,
        i.is_contract_b2b,
        i.is_rental_paid_in_advance,
        i.is_reversed,
        i.is_write_off,
        i.is_not_invoiceable_inconsiderable,
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
        CASE
            WHEN conta_contabil IN ('Cálculo Impostos', 'Late Payment Fee', 'Receita - Antecipação MRA', 'Multa Condomínio', 'Multa Danos', 'Receita de Cartão de Crédito', 'Reserva', 'Receitas Financeiras', 'Notas Fiscais') THEN true
            ELSE false 
        END AS conta_resultado,
        SUM(
            CASE 
                WHEN bill_item = 'cap' THEN 1
                ELSE 0
            END
        ) OVER (PARTITION BY i.sk_contract, i.accrual_year_month, conta_contabil) > 0 AS has_paid_amount,
        SUM(
            CASE 
                WHEN NOT(bill_item = 'cap') THEN 1
                ELSE 0
            END
        ) OVER (PARTITION BY i.sk_contract, i.accrual_year_month, conta_contabil) > 0 AS has_receivable_amount,
        IF(NOT(
        (status != 'not-invoiceable') OR 
        (status = 'not-invoiceable' AND entry_accrual_year_month >= 202508) OR 
        (status = 'not-invoiceable' AND entry_accrual_year_month >= 202506 AND to_account_type = 'contract' AND bill_item IN ('early termination fee', 'early termination fee non protection')) OR
        (status = 'not-invoiceable' AND bill_item = 'condominium fine') 
        ), TRUE, FALSE) AS is_not_invoiceable_inconsiderable_workaround,
        IF(
        NOT(status = 'not-invoiceable' AND entry_accrual_year_month >= 202506 AND to_account_type = 'contract' AND bill_item IN ('early termination fee', 'early termination fee non protection')), TRUE, FALSE
        ) AS is_not_invoiceable_inconsiderable_early_termination,
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
        i.contract_annulment
    FROM
        invoice_classification AS i 
