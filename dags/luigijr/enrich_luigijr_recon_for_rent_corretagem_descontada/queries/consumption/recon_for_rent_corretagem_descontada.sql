WITH

-- Corte de saldo: quais contratos ainda têm saldo relevante no fechamento. Só o sk_contract sobrevive daqui — serve de filtro, não de dado.
invoice_all_cutoff AS (
    SELECT
        sk_contract,
        account_type,
        SUM(due_amount) OVER (PARTITION BY sk_contract, account_type) AS contract_balance_cutoff
    FROM dw_fintech_snapshot_recon.cap_union_invoice_snapshot
    WHERE TRUE
        AND year  = year(current_date())
        AND month = month(current_date())
        AND (
            (bill_item = 'brokerage quinto andar'
                AND description LIKE '%dito - Parcelamento corretagem - QuintoAndar%')
            OR (bill_item = 'brokerage installment')
        )
        AND contract_status IN ('Ativo', 'Finalizado')
        AND account_type = 'landlord'
        -- Floor do corte: 2024-01-01
        AND (
            (status IN ('open', 'divergent payment', 'paid', 'written down', 'not payable')
                AND CAST(CAST(entry_created_date AS TIMESTAMP) AS DATE) >= DATE('2024-01-01')
                AND CAST(CAST(entry_created_date AS TIMESTAMP) AS DATE) <= last_day(add_months(current_date(), -1)))
            OR (status = 'canceled'
                AND CAST(CAST(invoice_canceled_date AS TIMESTAMP) AS DATE) > last_day(add_months(current_date(), -1))
                AND CAST(CAST(entry_created_date AS TIMESTAMP) AS DATE) >= DATE('2024-01-01')
                AND CAST(CAST(entry_created_date AS TIMESTAMP) AS DATE) <= last_day(add_months(current_date(), -1)))
            -- Dia 19 do mês anterior à competência: é quando a fatura seguinte é gerada, então não-faturável criado a partir daí já pertence ao fechamento.
            OR (status = 'not-invoiceable'
                AND CAST(CAST(entry_created_date AS TIMESTAMP) AS DATE) >=
                    date_add(trunc(add_months(current_date(), -2), 'MONTH'), 19)
                AND CAST(CAST(entry_created_date AS TIMESTAMP) AS DATE) <= last_day(add_months(current_date(), -1)))
        )
),

-- Materialidade de R$ 0,99: contrato que zerou não compõe a conta. O DISTINCT é necessário porque o CTE acima usa window, não GROUP BY.
saldo_cutoff AS (
    SELECT DISTINCT sk_contract, account_type, contract_balance_cutoff
    FROM invoice_all_cutoff
    WHERE ABS(contract_balance_cutoff) > 0.99
),

-- Sinal invertido: a conta é passiva, e o razão a lê como crédito.
invoice_all AS (
    SELECT
        ia.id_entry,
        ia.id_invoice,
        ia.sk_contract,
        ia.accounting_version,
        ia.bill_item,
        ia.description,
        ia.locale,
        ia.localidade,
        ia.account_type,
        ia.status,
        -1.0000 * ia.due_amount AS due_amount,
        ia.accrual_year_month,
        ia.entry_accrual_year_month,
        CAST(CAST(ia.entry_created_date      AS TIMESTAMP) AS DATE) AS entry_created_date,
        CAST(CAST(ia.invoice_due_date        AS TIMESTAMP) AS DATE) AS invoice_due_date,
        CAST(CAST(ia.real_invoice_paid_date  AS TIMESTAMP) AS DATE) AS real_invoice_paid_date,
        CAST(CAST(ia.invoice_canceled_date   AS TIMESTAMP) AS DATE) AS invoice_canceled_date,
        CAST(CAST(ia.invoice_write_off_date  AS TIMESTAMP) AS DATE) AS write_off_at,
        ia.ended_before_started,
        ia.is_reversed,
        ia.contract_status,
        SUM(ia.due_amount) OVER (PARTITION BY ia.sk_contract, ia.account_type) AS contract_balance
    FROM dw_fintech_snapshot_recon.cap_union_invoice_snapshot ia
    WHERE TRUE
        AND ia.year  = year(current_date())
        AND ia.month = month(current_date())
        AND (
            (ia.bill_item = 'brokerage quinto andar'
                AND ia.description LIKE '%dito - Parcelamento corretagem - QuintoAndar%')
            OR (ia.bill_item = 'brokerage installment')
        )
        AND ia.contract_status IN ('Ativo', 'Finalizado')
        AND ia.account_type = 'landlord'
        -- Janela: 2015-01-01
        AND (
            (ia.status IN ('open', 'divergent payment', 'paid', 'written down', 'not payable')
                AND CAST(CAST(ia.entry_created_date AS TIMESTAMP) AS DATE) >= DATE('2015-01-01')
                AND CAST(CAST(ia.entry_created_date AS TIMESTAMP) AS DATE) <= last_day(add_months(current_date(), -1)))
            OR (ia.status = 'canceled'
                AND CAST(CAST(ia.invoice_canceled_date AS TIMESTAMP) AS DATE) > last_day(add_months(current_date(), -1))
                AND CAST(CAST(ia.entry_created_date AS TIMESTAMP) AS DATE) >= DATE('2015-01-01')
                AND CAST(CAST(ia.entry_created_date AS TIMESTAMP) AS DATE) <= last_day(add_months(current_date(), -1)))
            -- Diferente da 211412: aqui o braço not-invoiceable TEM teto de data. Por isso esta conta não precisa da limpeza D+2 separada.
            OR (ia.status = 'not-invoiceable'
                AND CAST(CAST(ia.entry_created_date AS TIMESTAMP) AS DATE) >=
                    date_add(trunc(add_months(current_date(), -2), 'MONTH'), 19)
                AND CAST(CAST(ia.entry_created_date AS TIMESTAMP) AS DATE) <= last_day(add_months(current_date(), -1)))
        )
        AND ia.sk_contract IN (SELECT sk_contract FROM saldo_cutoff)
),

-- Contadores que identificam lançamento e contralançamento do mesmo valor na mesma fatura, e a marcação do par que se anula.
sanitization AS (
    SELECT
        *,
        CASE
            WHEN due_amount > 0 AND rn_sanitization <= negative_entries_count THEN TRUE
            WHEN due_amount < 0 AND rn_sanitization <= positive_entries_count THEN TRUE
            ELSE FALSE
        END AS opposite_entries
    FROM (
        SELECT
            *,
            COUNT(CASE WHEN due_amount > 0 THEN 1 END)
                OVER (PARTITION BY sk_contract, id_invoice, bill_item, ABS(due_amount)) AS positive_entries_count,
            COUNT(CASE WHEN due_amount < 0 THEN 1 END)
                OVER (PARTITION BY sk_contract, id_invoice, bill_item, ABS(due_amount)) AS negative_entries_count,
            ROW_NUMBER()
                OVER (PARTITION BY sk_contract, id_invoice, bill_item, due_amount
                      ORDER BY entry_created_date ASC, id_entry ASC) AS rn_sanitization
        FROM invoice_all
    )
),

composicao AS (
    SELECT
        id_entry,
        id_invoice,
        sk_contract,
        accounting_version,
        bill_item,
        description,
        locale,
        localidade,
        account_type,
        status,
        CAST(due_amount AS DOUBLE) AS due_amount,
        accrual_year_month,
        entry_accrual_year_month,
        entry_created_date,
        invoice_due_date,
        real_invoice_paid_date,
        invoice_canceled_date,
        write_off_at,
        ended_before_started,
        is_reversed,
        contract_status,
        opposite_entries,
        CAST(contract_balance AS DOUBLE) AS contract_balance,
        CASE WHEN due_amount > 0 THEN 'Crédito' ELSE 'Débito' END AS sinal,
        CASE WHEN bill_item = 'brokerage installment' THEN 'Parcela'
             ELSE 'Crédito p/ parcelamento' END                   AS tipo
    FROM sanitization
    WHERE TRUE
        AND opposite_entries = FALSE
        AND ABS(contract_balance) > 0.99
)

SELECT
    id_entry,
    id_invoice,
    sk_contract,
    accounting_version,
    bill_item,
    description,
    locale,
    localidade,
    account_type,
    status,
    due_amount,
    accrual_year_month,
    entry_accrual_year_month,
    entry_created_date,
    invoice_due_date,
    real_invoice_paid_date,
    invoice_canceled_date,
    write_off_at,
    ended_before_started,
    is_reversed,
    contract_status,
    opposite_entries,
    contract_balance,
    sinal,
    tipo,
    '211413'                                 AS conta_numero,
    'Corretagem a ser Descontada'            AS conta_nome,
    last_day(add_months(current_date(), -1)) AS data_fim,
    current_timestamp()                      AS gerado_em,
    date_format(current_date(), 'yyyyMM')    AS snapshot,
    TRUE                                     AS entra_no_saldo
FROM composicao
