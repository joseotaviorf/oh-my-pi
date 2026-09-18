WITH

-- Corte de saldo: quais contratos ainda têm saldo relevante no fechamento. Só o sk_contract sobrevive daqui — serve de filtro, não de dado.
invoice_all_cutoff AS (
    SELECT
        sk_contract,
        account_type,
        SUM(due_amount) AS saldo_cutoff
    FROM dw_fintech_snapshot_recon.cap_union_invoice_snapshot
    WHERE TRUE
        AND year  = year(current_date())
        AND month = month(current_date())
        AND bill_item = 'brokerage quinto andar postponed'
        AND contract_status IN ('Ativo', 'Finalizado')
        AND account_type = 'landlord'
        AND (ended_before_started = FALSE OR ended_before_started IS NULL)
        AND (
            (status IN ('open', 'divergent payment', 'paid', 'written down', 'not payable')
                AND CAST(CAST(entry_created_date AS TIMESTAMP) AS DATE) >= DATE('2023-01-01')
                AND CAST(CAST(entry_created_date AS TIMESTAMP) AS DATE) <= last_day(add_months(current_date(), -1)))
            OR (status = 'canceled'
                AND CAST(CAST(invoice_canceled_date AS TIMESTAMP) AS DATE) > last_day(add_months(current_date(), -1))
                AND CAST(CAST(entry_created_date AS TIMESTAMP) AS DATE) >= DATE('2023-01-01')
                AND CAST(CAST(entry_created_date AS TIMESTAMP) AS DATE) <= last_day(add_months(current_date(), -1)))
            -- Dia 19 do mês anterior à competência: é quando a fatura seguinte é gerada, então não-faturável criado a partir daí já pertence ao fechamento.
            OR (status = 'not-invoiceable'
                AND CAST(CAST(entry_created_date AS TIMESTAMP) AS DATE) >=
                    date_add(trunc(add_months(current_date(), -2), 'MONTH'), 19))
        )
    GROUP BY 1, 2
),

-- Materialidade de R$ 0,99: contrato que zerou não compõe a conta.
saldo_cutoff AS (
    SELECT *
    FROM invoice_all_cutoff
    WHERE ABS(saldo_cutoff) > 0.99
),

-- Volta na snap trazendo TODAS as entradas dos contratos que passaram no corte, inclusive as que sozinhas não passariam. Sinal invertido: a conta é passiva, e o razão a lê como crédito.
invoice_all AS (
    SELECT
        ss.id_entry,
        ss.id_invoice,
        ct.sk_contract,
        ss.accounting_version,
        ss.bill_item,
        ss.description,
        ss.locale,
        ss.localidade,
        ct.account_type,
        ss.status,
        -1.0000 * ss.due_amount AS due_amount,
        ss.accrual_year_month,
        ss.entry_accrual_year_month,
        CAST(CAST(ss.entry_created_date      AS TIMESTAMP) AS DATE) AS entry_created_date,
        CAST(CAST(ss.invoice_due_date        AS TIMESTAMP) AS DATE) AS invoice_due_date,
        CAST(CAST(ss.real_invoice_paid_date  AS TIMESTAMP) AS DATE) AS real_invoice_paid_date,
        CAST(CAST(ss.invoice_canceled_date   AS TIMESTAMP) AS DATE) AS invoice_canceled_date,
        CAST(CAST(ss.invoice_write_off_date  AS TIMESTAMP) AS DATE) AS write_off_at,
        ss.ended_before_started,
        ss.contract_status
    FROM saldo_cutoff ct
    LEFT JOIN dw_fintech_snapshot_recon.cap_union_invoice_snapshot ss
        ON ct.sk_contract = ss.sk_contract
    WHERE TRUE
        AND ss.year  = year(current_date())
        AND ss.month = month(current_date())
        AND ss.bill_item = 'brokerage quinto andar postponed'
        AND ss.contract_status IN ('Ativo', 'Finalizado')
        AND (ss.ended_before_started = FALSE OR ss.ended_before_started IS NULL)
        AND ss.due_amount != 0
),

-- Janela da competência + os contadores que identificam lançamento e contralançamento do mesmo valor na mesma fatura.
date_filtering AS (
    SELECT
        *,
        SUM(-1.0000 * due_amount)
            OVER (PARTITION BY sk_contract, account_type) AS contract_balance,
        COUNT(CASE WHEN due_amount > 0 THEN 1 END)
            OVER (PARTITION BY sk_contract, id_invoice, bill_item, ABS(due_amount)) AS positive_entries_count,
        COUNT(CASE WHEN due_amount < 0 THEN 1 END)
            OVER (PARTITION BY sk_contract, id_invoice, bill_item, ABS(due_amount)) AS negative_entries_count,
        ROW_NUMBER()
            OVER (PARTITION BY sk_contract, id_invoice, bill_item, due_amount
                  ORDER BY entry_created_date ASC, id_entry ASC) AS rn_sanitization
    FROM invoice_all
    WHERE (
        (status IN ('open', 'divergent payment', 'paid', 'written down', 'not payable')
            AND entry_created_date >= DATE('2023-01-01')
            AND entry_created_date <= last_day(add_months(current_date(), -1)))
        OR (status = 'canceled'
            AND invoice_canceled_date > last_day(add_months(current_date(), -1))
            AND entry_created_date >= DATE('2023-01-01')
            AND entry_created_date <= last_day(add_months(current_date(), -1)))
        OR (status = 'not-invoiceable'
            AND entry_created_date >=
                date_add(trunc(add_months(current_date(), -2), 'MONTH'), 19))
    )
),

-- Marca o par lançamento/contralançamento que se anula.
sanitization AS (
    SELECT
        *,
        CASE
            WHEN due_amount > 0 AND rn_sanitization <= negative_entries_count THEN TRUE
            WHEN due_amount < 0 AND rn_sanitization <= positive_entries_count THEN TRUE
            ELSE FALSE
        END AS opposite_entries
    FROM date_filtering
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
        CAST(due_amount AS DOUBLE)       AS due_amount,
        accrual_year_month,
        entry_accrual_year_month,
        entry_created_date,
        invoice_due_date,
        real_invoice_paid_date,
        invoice_canceled_date,
        write_off_at,
        ended_before_started,
        contract_status,
        opposite_entries,
        CAST(contract_balance AS DOUBLE) AS contract_balance
    FROM sanitization
    WHERE TRUE
        AND opposite_entries = FALSE
        AND ABS(contract_balance) > 0.99
        AND entry_created_date <= last_day(add_months(current_date(), -1))
),

casos_2023 AS (
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
        CAST(due_amount AS DOUBLE)       AS due_amount,
        accrual_year_month,
        entry_accrual_year_month,
        to_date(entry_created_date)      AS entry_created_date,
        to_date(invoice_due_date)        AS invoice_due_date,
        to_date(real_invoice_paid_date)  AS real_invoice_paid_date,
        to_date(invoice_canceled_date)   AS invoice_canceled_date,
        to_date(write_off_at)            AS write_off_at,
        CAST(ended_before_started AS BOOLEAN) AS ended_before_started,
        contract_status,
        CAST(opposite_entries AS BOOLEAN) AS opposite_entries,
        CAST(contract_balance AS DOUBLE) AS contract_balance
    FROM datalake_gsheets_clean.recon_rent_corr_post_antes_2023
),

base AS (
    SELECT *, 'A partir de 2023' AS periodo FROM composicao
    UNION ALL
    SELECT *, 'Anterior a 2023'  AS periodo FROM casos_2023
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
    contract_status,
    opposite_entries,
    contract_balance,
    periodo,
    '211412'                              AS conta_numero,
    'Corretagem Postergada'               AS conta_nome,
    last_day(add_months(current_date(), -1)) AS data_fim,
    current_timestamp()                   AS gerado_em,
    date_format(current_date(), 'yyyyMM')    AS snapshot,
    (periodo = 'A partir de 2023')        AS entra_no_saldo
FROM base
