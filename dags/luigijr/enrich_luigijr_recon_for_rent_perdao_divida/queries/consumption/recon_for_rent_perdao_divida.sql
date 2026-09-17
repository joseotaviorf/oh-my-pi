WITH

-- Escopo da snap: os três bill_item de perdão, contrato ativo ou finalizado, e fora de write-off. Sinal invertido: a conta é de despesa, e o razão a lê como débito.
invoice_all AS (
    SELECT
        id_entry,
        id_invoice,
        sk_contract,
        accounting_version,
        bill_item,
        description,
        account_type,
        status,
        -1.00000 * due_amount AS due_amount,
        accrual_year_month,
        CAST(CAST(entry_created_date     AS TIMESTAMP) AS DATE) AS entry_created_date,
        CAST(CAST(real_invoice_paid_date AS TIMESTAMP) AS DATE) AS real_invoice_paid_date,
        CAST(CAST(invoice_canceled_date  AS TIMESTAMP) AS DATE) AS invoice_canceled_date,
        CAST(CAST(invoice_write_off_date AS TIMESTAMP) AS DATE) AS write_off_at,
        contract_status
    FROM dw_fintech_snapshot_recon.cap_union_invoice_snapshot
    WHERE TRUE
        AND year  = year(current_date())
        AND month = month(current_date())
        AND bill_item IN ('collections negotiation',
                          'evictions debt relief',
                          'evictions debt relief negotiation')
        AND contract_status IN ('Ativo', 'Finalizado')
        AND (is_write_off = FALSE OR is_write_off IS NULL)
        -- Janela do ts_snapshot: só a extração do mês corrente.
        AND CAST(CAST(ts_snapshot AS TIMESTAMP) AS DATE) >= trunc(current_date(), 'MONTH')
        AND CAST(CAST(ts_snapshot AS TIMESTAMP) AS DATE) <  add_months(trunc(current_date(), 'MONTH'), 1)
),

-- Janela da competência + os contadores que identificam lançamento e contralançamento do mesmo valor na mesma fatura.

-- Quatro braços, e cada um usa uma data de referência diferente: pago no ano, não faturável criado no ano, cancelado depois do fechamento mas pago dentro do ano, e cancelado dentro do ano tendo sido pago antes dele.
date_filtering AS (
    SELECT
        *,
        COUNT(CASE WHEN due_amount > 0 THEN 1 END)
            OVER (PARTITION BY sk_contract, id_invoice, bill_item, ABS(due_amount)) AS positive_entries_count,
        COUNT(CASE WHEN due_amount < 0 THEN 1 END)
            OVER (PARTITION BY sk_contract, id_invoice, bill_item, ABS(due_amount)) AS negative_entries_count,
        ROW_NUMBER()
            OVER (PARTITION BY sk_contract, id_invoice, bill_item, due_amount
                  ORDER BY entry_created_date ASC) AS rn_sanitization
    FROM invoice_all
    WHERE (
        (status IN ('paid', 'divergent payment')
            AND real_invoice_paid_date >= trunc(add_months(current_date(), -1), 'YEAR')
            AND real_invoice_paid_date <= last_day(add_months(current_date(), -1)))
        OR (status IN ('not payable')
            AND entry_created_date >= trunc(add_months(current_date(), -1), 'YEAR')
            AND entry_created_date <= last_day(add_months(current_date(), -1)))
        OR (status = 'canceled'
            AND invoice_canceled_date > last_day(add_months(current_date(), -1))
            AND real_invoice_paid_date >= trunc(add_months(current_date(), -1), 'YEAR')
            AND real_invoice_paid_date <= last_day(add_months(current_date(), -1)))
        OR (status = 'canceled'
            AND invoice_canceled_date >= trunc(add_months(current_date(), -1), 'YEAR')
            AND invoice_canceled_date <= last_day(add_months(current_date(), -1))
            AND real_invoice_paid_date < trunc(add_months(current_date(), -1), 'YEAR'))
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
        account_type,
        status,
        -- Exceção do 4º braço: cancelada dentro da janela e paga antes dela entra invertida, como débito. As condições são idênticas às do braço.
        CAST(
            CASE
                WHEN status = 'canceled'
                     AND invoice_canceled_date >= trunc(add_months(current_date(), -1), 'YEAR')
                     AND invoice_canceled_date <= last_day(add_months(current_date(), -1))
                     AND real_invoice_paid_date < trunc(add_months(current_date(), -1), 'YEAR')
                THEN -1.00000 * due_amount
                ELSE due_amount
            END
        AS DOUBLE) AS due_amount,
        accrual_year_month,
        entry_created_date,
        real_invoice_paid_date,
        invoice_canceled_date,
        write_off_at,
        contract_status,
        CASE
            WHEN due_amount > 0 AND rn_sanitization <= negative_entries_count THEN TRUE
            WHEN due_amount < 0 AND rn_sanitization <= positive_entries_count THEN TRUE
            ELSE FALSE
        END AS opposite_entries
    FROM date_filtering
)

SELECT
    id_entry,
    id_invoice,
    sk_contract,
    accounting_version,
    bill_item,
    description,
    account_type,
    status,
    due_amount,
    accrual_year_month,
    entry_created_date,
    real_invoice_paid_date,
    invoice_canceled_date,
    write_off_at,
    contract_status,
    opposite_entries,
    '513006'                                 AS conta_numero,
    'Perdão de Dívida - Losses'              AS conta_nome,
    last_day(add_months(current_date(), -1)) AS data_fim,
    current_timestamp()                      AS gerado_em,
    date_format(current_date(), 'yyyyMM')    AS snapshot,
    TRUE                                     AS entra_no_saldo
FROM composicao
