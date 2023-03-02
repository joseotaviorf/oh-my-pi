WITH invoice_snapshot AS (
    SELECT
        sk_invoice AS id_external,
        frequency AS purpose,
        accrual_year_month,
        dt_sent AS ts_sent,
        dt_due AS ts_due,
        dt_paid AS ts_paid,
        due_amount,
        user,
        payment_status AS status,
        paid_amount,
        CASE
            WHEN date_trunc('DAY', ts_created) <= (date_trunc('MONTH', DATE(ts_snapshot)) - INTERVAL 1 DAY) AND (dt_paid IS NULL OR DATE_TRUNC('DAY', dt_paid) >= (date_trunc('MONTH', DATE(ts_snapshot)) - INTERVAL 1 DAY)) THEN 1
            ELSE 0
        END AS Flag_fechamento,
        DATE(ts_created) AS ts_created,
        ts_snapshot AS ts_snapshot_dim,
        year,
        month,
        day
    FROM
        dw_payment_snapshot.dim_invoice_snapshot
    WHERE
        due_amount < 0
        AND payment_status <> 'canceled'
),
entry_snapshot AS (
    SELECT DISTINCT
        b1.sk_invoice,
        b2.accrual_year_month,
        b2.ts_snapshot AS ts_snapshot_dim_entry,
        b1.ts_snapshot AS ts_snapshot_fact_entries,
        b2.year,
        b2.month,
        b2.day
    FROM
        dw_payment_snapshot.dim_invoice_entry_snapshot AS b2
    LEFT JOIN
        dw_payment_snapshot.fact_invoice_entries_snapshot AS b1
            ON b1.sk_invoice_entry = b2.sk_invoice_entry
            AND b1.YEAR = b2.YEAR
            AND b1.MONTH = b2.MONTH
            AND b1.DAY = b2.DAY
    WHERE
        TRIM(UPPER(b2.description)) LIKE '%ACORDO COBRAN%'
        AND TRIM(UPPER(b2.entry_type)) LIKE '%INSURANCE GUARANTEE%'
),
fact_snapshot AS (
    SELECT DISTINCT
        sk_invoice,
        sk_contract,
        sk_region,
        ts_snapshot AS ts_snapshot_fact,
        year,
        month,
        day
    FROM
        dw_payment_snapshot.fact_invoice_entries_snapshot
),
base_venc_full AS (
    SELECT
        CAST(CONCAT(YEAR((DATEADD(DAY, -30, ts_due))), LPAD(MONTH(DATEADD(DAY, -30, ts_due)), 2, 0)) AS INT) AS accrual_year_month,
        DATE(ts_due) AS due_date,
        COUNT(*) AS incidencias
    FROM
        datalake_retsuko_clean.boleto
    WHERE
        identifier LIKE '%B%'
    GROUP BY 1, 2
),
base_venc_tratamento AS (
    SELECT
        accrual_year_month,
        MAX(incidencias) AS max_incidencias
    FROM
        base_venc_full
    GROUP BY 1
),
base_vencimento AS (
    SELECT
        b1.accrual_year_month,
        b1.due_date
    FROM
        base_venc_full AS b1
    INNER JOIN base_venc_tratamento AS b2
        ON b2.accrual_year_month = b1.accrual_year_month
        AND b1.incidencias = b2.max_incidencias
),
base_invoice AS (
    SELECT
        i.id_external AS invoice_id,
        dc.sk_contract AS contract_id,
        COALESCE(DATE(dc.ts_signature), DATE(dc.dt_start)) AS contract_signature_date,
        dc.version AS contract_version,
        CASE
            WHEN i.purpose = 'monthly' THEN 'Mensal'
            WHEN i.purpose = 'onboarding' THEN 'Onboarding'
            WHEN i.purpose = 'extra' THEN 'Extra'
            WHEN i.purpose = 'early termination' THEN 'Rescisão'
            ELSE i.purpose
        END AS invoice_type,
        i.accrual_year_month AS accrual_year_month,
        e.accrual_year_month AS competencia_invoice_renegociada,
        CASE
            WHEN e.sk_invoice IS NOT NULL THEN COALESCE(ve.due_date, i.ts_due)
            WHEN i.purpose = 'monthly' THEN COALESCE(vi.due_date, i.ts_due)
            ELSE i.ts_due
        END AS invoice_original_due_date,
        i.ts_due AS invoice_due_date,
        (i.due_amount *(-1)) AS invoice_amount,
        CASE
            WHEN i.status = 'paid' THEN 'Pago'
            WHEN i.status = 'open' THEN 'Em aberto'
            WHEN i.status = 'canceled' THEN 'Cancelado'
            WHEN i.status = 'written down' THEN 'Baixado'
            ELSE i.status
        END AS invoice_status,
        i.paid_amount AS invoice_paid_amount,
        i.ts_paid AS invoice_paid_date,
        dc.guarantee,
        CASE
            WHEN i.user = 'tenant' THEN 'Inquilino'
            WHEN i.user = 'landlord' THEN 'Proprietario'
            ELSE ''
        END AS invoice_account_type,
        i.ts_created AS invoice_created_at,
        i.ts_sent AS invoice_sent_at,
        CASE
            WHEN dr.city_name IS NULL THEN 'São Paulo'
            ELSE dr.city_name
        END AS city_name,
        CASE
            WHEN dr.city_group IS NULL THEN 'RMSP'
            ELSE dr.city_group
        END AS city_group,
        i.ts_snapshot_dim,
        f.ts_snapshot_fact,
        e.ts_snapshot_dim_entry,
        e.ts_snapshot_fact_entries,
        dc.ts_snapshot AS ts_snapshot_dim_contract,
        ROW_NUMBER() OVER (PARTITION BY dc.sk_contract, i.id_external, i.year, i.month, i.day ORDER BY i.ts_created DESC) AS RN,
        i.year,
        i.month,
        i.day
    FROM
        invoice_snapshot AS i
    LEFT JOIN fact_snapshot AS f
        ON i.id_external = f.sk_invoice
        AND i.year = f.year
        AND i.month = f.month
        AND i.day = f.day
    LEFT JOIN entry_snapshot AS e
        ON i.id_external = e.sk_invoice
        AND i.year = f.year
        AND i.month = f.month
        AND i.day = f.day
    LEFT JOIN base_vencimento AS vi
        ON vi.accrual_year_month = i.accrual_year_month
    LEFT JOIN base_vencimento AS ve
        ON ve.accrual_year_month = e.accrual_year_month
    LEFT JOIN dw_public_snapshot.dim_contract_snapshot AS dc
        ON f.sk_contract = dc.sk_contract
        AND dc.year = f.year
        AND dc.month = f.month
        AND dc.day = f.day
    LEFT JOIN dw_public.dim_region AS dr
        ON f.sk_region = dr.sk_region
    WHERE i.flag_fechamento = 1
),
atraso_contaminado AS (
    SELECT
        contract_id,
        invoice_account_type,
        year,
        month,
        day,
        MIN(CAST(invoice_original_due_date AS TIMESTAMP)) AS contract_due_date_min
    FROM
        base_invoice
    WHERE
        RN = 1
    GROUP BY 1, 2, 3, 4, 5
),
invoice_qty AS (
    SELECT
        contract_id,
        year,
        month,
        day,
        COUNT(*) AS qty_invoice
    FROM
        base_invoice
    WHERE
        RN = 1
    GROUP BY 1, 2, 3, 4
),
base_tratada AS (
    SELECT
        a.*,
        c.qty_invoice,
        b.contract_due_date_min,
        a.year,
        a.month,
        a.day,
        EXTRACT( DAY FROM ((date_trunc('MONTH', DATE(MAKE_DATE(a.year, a.month, a.day))) - INTERVAL 1 DAY) -  CAST(a.invoice_original_due_date AS TIMESTAMP))) AS delay_invoice_at_closure,
        EXTRACT( DAY FROM ((date_trunc('MONTH', DATE(MAKE_DATE(a.year, a.month, a.day))) - INTERVAL 1 DAY) - b.contract_due_date_min)) AS delay_contamined_at_closure
    FROM
        base_invoice AS a
    LEFT JOIN atraso_contaminado AS b
        ON a.contract_id = b.contract_id
        AND a.invoice_account_type = b.invoice_account_type
        AND a.year = b.year
        AND a.month = b.month
        AND a.day = b.day
    LEFT JOIN invoice_qty AS c
        ON a.contract_id = c.contract_id
        AND a.year = c.year
        AND a.month = c.month
        AND a.day = c.day
    WHERE
        a.RN = 1
),
base_atraso AS (
    SELECT
        *,
        CASE
            WHEN delay_invoice_at_closure <= 0 THEN 'a. Current'
            WHEN delay_invoice_at_closure <= 30 THEN 'b. 1-30'
            WHEN delay_invoice_at_closure <= 60 THEN 'c. 31-60'
            WHEN delay_invoice_at_closure <= 90 THEN 'd. 61-90'
            WHEN delay_invoice_at_closure <= 120 THEN 'e. 91-120'
            WHEN delay_invoice_at_closure <= 150 THEN 'f. 121-150'
            WHEN delay_invoice_at_closure <= 180 THEN 'g. 151-180'
            ELSE 'h. acima de 180'
        END AS delay_invoice_range,
        CASE
            WHEN delay_contamined_at_closure <= 0 THEN 'a. Current'
            WHEN delay_contamined_at_closure <= 30 THEN 'b. 1-30'
            WHEN delay_contamined_at_closure <= 60 THEN 'c. 31-60'
            WHEN delay_contamined_at_closure <= 90 THEN 'd. 61-90'
            WHEN delay_contamined_at_closure <= 120 THEN 'e. 91-120'
            WHEN delay_contamined_at_closure <= 150 THEN 'f. 121-150'
            WHEN delay_contamined_at_closure <= 180 THEN 'g. 151-180'
            ELSE 'h. acima de 180'
        END AS delay_contamined_range,
        year,
        month,
        day
    FROM
        base_tratada
),
----------- OLD RULES (until dec/2022)
distinct_invoice_types AS (
    SELECT DISTINCT
        contract_id,
        invoice_type,
        year,
        month,
        day
    FROM
        base_atraso
    WHERE year < 2023
),
BaseTipoBoleto AS (
    SELECT DISTINCT
        contract_id,
        SUM(CASE
                WHEN invoice_type = 'Mensal' THEN 1
                ELSE 0
            END) AS flagMensal,
        SUM(CASE
                WHEN invoice_type = 'Onboarding' THEN 1
                ELSE 0
            END) AS flagOnboarding,
        SUM(CASE
                WHEN invoice_type = 'Extra' THEN 1
                ELSE 0
            END) AS flagExtra,
        SUM(CASE
                WHEN invoice_type = 'pos rental' THEN 1
                ELSE 0
            END) AS flagPosRental,
        SUM(CASE
                WHEN invoice_type = 'Rescisão' THEN 1
                ELSE 0
            END) AS flagRescisao,
        year,
        month,
        day
    FROM
        distinct_invoice_types
    GROUP BY 1, 7, 8, 9
),
BaseTipoBoleto2 AS (
    SELECT
        contract_id,
        flagMensal,
        flagOnboarding,
        flagExtra,
        flagPosRental,
        flagRescisao,
        CASE
            WHEN (flagMensal = 1 OR flagOnboarding = 1)
                AND flagExtra = 0
                AND flagPosRental = 0
                AND flagRescisao = 0
            THEN 'a.Mensal_Onboarding'
            ELSE 'b.Extra_Rescisao'
        END AS GrupoProvisao,
        year,
        month,
        day
    FROM
        BaseTipoBoleto
),
cte_snapshots_final AS (
    SELECT
        bf.invoice_id AS id_invoice,
        bf.contract_id AS id_contract,
        bf.qty_invoice,
        bf.contract_version,
        bf.invoice_type,
        bf.competencia_invoice_renegociada AS invoice_competence_renegotiated,
        bf.invoice_amount,
        bf.invoice_status,
        bf.invoice_paid_amount,
        NULL AS invoice_paid_via,
        bf.guarantee,
        bf.invoice_account_type,
        NULL AS invoice_indentifier,
        NULL AS our_number,
        bf.delay_invoice_at_closure,
        bf.delay_contamined_at_closure,
        bf.delay_invoice_range,
        bf.delay_contamined_range,
        bf.city_name,
        bf.city_group,
        btb.GrupoProvisao AS provisional_group,
        bf.accrual_year_month,
        bf.contract_signature_date AS dt_contract_signature,
        bf.invoice_original_due_date AS dt_invoice_original_due,
        bf.invoice_due_date AS dt_invoice_due,
        bf.invoice_created_at AS dt_invoice_created,
        bf.invoice_sent_at AS dt_invoice_sent,
        bf.invoice_paid_date,
        bf.contract_due_date_min AS dt_contract_due_date_min,
        bf.year,
        bf.month,
        bf.day,
        FALSE AS is_historic_pdd
    FROM
        base_atraso AS bf
    LEFT JOIN BaseTipoBoleto2 AS btb
        ON bf.contract_id = btb.contract_id
        AND bf.year = btb.year
        AND bf.month = btb.month
        AND bf.day = btb.day
    WHERE bf.year < 2023 OR (bf.year=2023 AND bf.month=1)
),
historic_pdd AS (
    SELECT
        id_invoice,
        id_contract,
        qty_invoice,
        contract_version,
        invoice_type,
        invoice_competence_renegotiated,
        invoice_amount,
        invoice_status,
        invoice_paid_amount,
        invoice_paid_via,
        contract_guarantee,
        invoice_account_type,
        invoice_indentifier,
        our_number,
        delay_invoice_at_closure,
        delay_contamined_at_closure,
        delay_invoice_range,
        delay_contamined_range,
        city_name,
        city_group,
        provisional_group,
        accrual_year_month,
        dt_contract_signature,
        dt_invoice_original_due,
        dt_invoice_due,
        dt_invoice_created,
        dt_invoice_sent,
        invoice_paid_date,
        dt_contract_due_date_min,
        YEAR(dt_processing) AS year,
        MONTH(dt_processing) AS month,
        DAY(dt_processing) AS day,
        TRUE AS is_historic_pdd
    FROM datalake_gsheets_clean.base_pdd AS pdd
),
----------- NEW RULES (since jan/2023)
cte_snapshots_new_rules_final AS (
    SELECT
        bf.invoice_id AS id_invoice,
        bf.contract_id AS id_contract,
        bf.qty_invoice,
        bf.contract_version,
        bf.invoice_type,
        bf.competencia_invoice_renegociada AS invoice_competence_renegotiated,
        bf.invoice_amount,
        bf.invoice_status,
        bf.invoice_paid_amount,
        NULL AS invoice_paid_via,
        CASE
            WHEN bf.guarantee = 'SeguroFairfax'                              THEN 'Fairfax'
            WHEN bf.guarantee = 'PRO_GUARANTOR'                              THEN 'Pro_Guarantor'
            WHEN bf.guarantee = 'RentalGuarantee'                            THEN 'Rental_Guarantee'
            WHEN bf.guarantee = 'RentalDeposit' OR bf.guarantee = 'Deposito'    THEN 'Rental_Deposit'
            WHEN bf.guarantee = 'Standalone'                                 THEN 'Standalone'
            ELSE 'Outros'
        END AS contract_guarantee,
        bf.invoice_account_type,
        NULL AS invoice_indentifier,
        NULL AS our_number,
        bf.delay_invoice_at_closure,
        bf.delay_contamined_at_closure,
        bf.delay_invoice_range,
        bf.delay_contamined_range,
        bf.city_name,
        bf.city_group,
        CASE
            WHEN bf.guarantee IN ('PRO_GUARANTOR', 'RentalGuarantee', 'RentalDeposit','Deposito', 'Standalone')
            THEN 'd.Paid'
            ELSE 'c.Free'
        END AS provisional_group,
        bf.accrual_year_month,
        bf.contract_signature_date AS dt_contract_signature,
        bf.invoice_original_due_date AS dt_invoice_original_due,
        bf.invoice_due_date AS dt_invoice_due,
        bf.invoice_created_at AS dt_invoice_created,
        bf.invoice_sent_at AS dt_invoice_sent,
        bf.invoice_paid_date,
        bf.contract_due_date_min AS dt_contract_due_date_min,
        bf.year,
        bf.month,
        bf.day,
        FALSE AS is_historic_pdd
    FROM
        base_atraso AS bf
    WHERE year >= 2023 OR (year >= 2023 AND month <> 1)
)

SELECT * FROM cte_snapshots_final
UNION ALL
SELECT * FROM historic_pdd
UNION ALL
SELECT * FROM cte_snapshots_new_rules_final
