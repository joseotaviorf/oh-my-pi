WITH contracts AS (
    SELECT
        id AS id_contract,
        DATE(ts_signed) AS dt_signed,
        dt_started,
        COALESCE(dt_termination,current_date) AS last_month_vigency,
        ROUND(MONTHS_BETWEEN(COALESCE(dt_termination,current_date),dt_started)) AS total_months_vigency
    FROM 
        datalake_ebdb_clean.contract
    WHERE
        ts_signed IS NOT NULL
        AND status IN ('Ativo','Finalizado') 
),
payments AS (
    SELECT 
        fie.sk_contract,
        di.accrual_year_month,
        SUM(fie.brl_entry_due_amount) AS brl_entry_due_amount,
        SUM(CASE
                WHEN di.payment_status = 'not payable' THEN fie.brl_entry_due_amount
                ELSE fie.brl_entry_paid_amount END)
        AS brl_entry_paid_amount 
    FROM 
        dw_payment.fact_invoice_entries AS fie
    INNER JOIN 
        dw_payment.dim_invoice_entry AS dentry
            ON fie.sk_invoice_entry = dentry.sk_invoice_entry
    INNER JOIN 
        dw_payment.dim_invoice AS di
            ON fie.sk_invoice = di.sk_invoice
    WHERE
        dentry.entry_type IN ('rental anticipation fee','brokerage installment fee', 'installment lra', 'fine and interest','property damage fine') 
        AND from_account_type IN ('tenant','landlord')
        AND to_account_type = 'contract'
    GROUP BY 1,2
),
mra AS (
    SELECT
    DISTINCT
        c.id_external AS id_contract,
        mra.id AS id_mra,
        mra.ts_accepted,
        mra.dt_reference
    FROM 
        datalake_fastforward_clean.anticipation AS mra
    INNER JOIN 
        datalake_fastforward_clean.contract AS c
            ON c.id = mra.id_contract
    WHERE 
        mra.ts_accepted is not NULL
),
lra AS (
    SELECT
    DISTINCT
        c.id_external AS id_contract,
        lra.id AS id_lra,
        lra.ts_signed,
        li.ts_expected_due
    FROM 
        datalake_fastforward_clean.long_term_anticipation AS lra
    INNER JOIN 
        datalake_fastforward_clean.contract AS c
            ON lra.id_contract = c.id
    INNER JOIN 
        datalake_fastforward_clean.lra_installment AS li
            ON lra.id = li.id_long_term_anticipation
    WHERE
        lra.ts_signed IS NOT NULL
),
bfi AS (
    WITH 
    brokerage_finance AS (
        SELECT
            bfi.id AS id_bfi,
            DATE_TRUNC('month', c.dt_validity) AS month_validity_start,
            ADD_MONTHS(DATE_TRUNC('month', c.dt_validity), bfi.installment_number) AS month_validity_end,
            c.id_external
        FROM 
            datalake_owner_fees_clean.contract_brokerage_fee AS bfi
        INNER JOIN 
            datalake_owner_fees_clean.contract AS c
                ON c.id = bfi.id_contract
        WHERE
            installment_number > 0
        )
    SELECT DISTINCT
        dd.month_start,
        bf.id_external AS id_contract,
        bf.id_bfi,
        ROUND(MONTHS_BETWEEN(dd.month_start, bf.month_validity_start)) AS installment
    FROM
        brokerage_finance AS bf
    INNER JOIN
        dw_public.dim_date AS dd
            ON dd.month_start BETWEEN bf.month_validity_start AND bf.month_validity_end
    WHERE
        ROUND(MONTHS_BETWEEN(dd.month_start, bf.month_validity_start)) > 0
        AND month_start <= DATE_TRUNC('month',current_date)
),
lpf_rent AS (
    SELECT
        f.sk_contract,
        f.sk_invoice_entry AS id_lpf_rent,
        di.accrual_year_month
    FROM 
        dw_payment.fact_invoice_entries AS f
    INNER JOIN 
        dw_payment.dim_invoice_entry AS d
            ON f.sk_invoice_entry = d.sk_invoice_entry
    INNER JOIN 
        dw_payment.dim_invoice AS di
            ON f.sk_invoice = di.sk_invoice
    WHERE
        d.entry_type = 'fine and interest'
        AND from_account_type = 'tenant'
        AND to_account_type = 'contract'
),
lpf_condo AS (
    SELECT
        f.sk_contract,
        f.sk_invoice_entry AS id_lpf_condo,
        di.accrual_year_month
    FROM 
        dw_payment.fact_invoice_entries AS f
    INNER JOIN 
        dw_payment.dim_invoice_entry AS d
            ON f.sk_invoice_entry = d.sk_invoice_entry
    INNER JOIN 
        dw_payment.dim_invoice AS di
            ON f.sk_invoice = di.sk_invoice
    WHERE
        d.entry_type = 'property damage fine'
        AND d.description iLIKE '%quebra contratual%'
        AND from_account_type = 'tenant'
        AND to_account_type = 'contract'
),
reservation AS (
    WITH base_r AS (
        SELECT 
            rf.sk_contract AS id_contract, 
            dr.sk_reservation AS id_reservation,
            DATE(dr.ts_created) AS dt_created,
            CASE
                WHEN dr.installments <= 1 THEN DATE(dr.ts_created)
                ELSE ADD_MONTHS(DATE(dr.ts_created), (dr.installments - 1)) 
            END AS dt_end_payment,
            dr.value AS total_value,
            dr.value/dr.installments AS monthly_value
        FROM
            dw_public.dim_reservation AS dr
        INNER JOIN 
            dw_public.fact_listing_rent_flows AS rf
                ON dr.sk_reservation = rf.sk_reservation
        WHERE
            dr.sk_reservation > 0
            AND dr.is_ongoing IS NULL
            AND (dr.status IN ('FINISHED', 'CHARGED') OR (dr.status = 'CANCELED' AND (dr.cancellation_reason = 'TENANT_GAVE_UP' OR dr.cancellation_reason LIKE '%WITHOUT_CHARGE_BACK')))
            AND rf.sk_contract > 0
        )
    SELECT
    DISTINCT
        dd.month_start,
        br.id_contract,
        br.id_reservation,
        br.monthly_value
    FROM
         base_r AS br
    INNER JOIN 
        dw_public.dim_date AS dd
            ON dd.month_start BETWEEN DATE_TRUNC('month',br.dt_created) AND DATE_TRUNC('month',br.dt_end_payment)
),
ccp AS (
    SELECT
    DISTINCT
        c.id_external AS id_contract,
        ccp.id AS id_ccp,
        i.accrual_year_month,
        (i.paid_amount + i.due_amount) AS value
    FROM 
        datalake_retsuko_clean.credit_card_payment AS ccp
    INNER JOIN 
        datalake_retsuko_clean.invoice AS i
            ON ccp.id_invoice = i.id
    INNER JOIN 
        datalake_retsuko_clean.contract AS c
            ON i.id_contract = c.id
    WHERE 
        ccp.status = 'paid'
),
guarantee AS (
    WITH last_charge_created AS (
        SELECT 
            id,
            MAX(ts_created) AS ts_last_created
        FROM 
            datalake_rental_guarantee_clean.charge
        GROUP BY 1
        ),
    charge_info AS (
        SELECT
            c.id_guarantee,
            c.id,
            CASE
                WHEN c.charge_type = 'BILL' THEN 12
                ELSE c.installments
            END AS installments,
            c.charge_status,
            c.ts_created
        FROM
            datalake_rental_guarantee_clean.charge AS c
        INNER JOIN 
            last_charge_created AS lcu
                ON c.id = lcu.id
                AND c.ts_created = lcu.ts_last_created
            ),
    guarantee_base AS (
        SELECT 
            g.id_contract_ebdb as id_contract,
            g.id AS id_guarantee,
            ci.ts_created AS ts_charge_created,
            ci.id AS id_charge,
            ADD_MONTHS(DATE_TRUNC('month', ci.ts_created), ci.installments) AS dt_charge_end,
            DATE_TRUNC('month',ci.ts_created) AS dt_charge_started,
            ci.installments,
            ((g.final_value/100/installments)/1.0738)*0.825 AS monthly_revenue
        FROM 
            datalake_rental_guarantee_clean.guarantee AS g
        INNER JOIN 
            charge_info AS ci
                ON g.id = ci.id_guarantee
        WHERE
            g.id_contract_ebdb IS NOT NULL
            AND g.ts_paid IS NOT NULL
            AND g.guarantee_status IN ('ACTIVE','CANCELED')
            AND ci.charge_status = 'CAPTURED' 
        )
    SELECT DISTINCT
        gb.id_contract,
        gb.id_guarantee,
        gb.id_charge,
        dd.month_start AS accrual_year_month,
        (1+ROUND(MONTHS_BETWEEN(dd.month_start, ts_charge_created))) AS installment_number,
        gb.monthly_revenue
    FROM 
        guarantee_base AS gb
    INNER JOIN 
        dw_public.dim_date AS dd
            ON dd.date BETWEEN dt_charge_started AND dt_charge_end
    WHERE
        (1+ROUND(MONTHS_BETWEEN(dd.month_start, ts_charge_created))) <= installments
        AND dd.month_start <= current_date
)
SELECT DISTINCT
    COALESCE(DATE_FORMAT(dd.month_start, 'yyyyMMdd'), -1) AS month_start,
    COALESCE(b.id_contract, -1) AS id_contract,
    COALESCE(lpf_rent.id_lpf_rent, -1) AS id_lpf_rent,
    COALESCE(lpf_condo.id_lpf_condo, -1) AS id_lpf_condo,
    COALESCE(mra.id_mra, -1) AS id_mra,
    COALESCE(lra.id_lra, -1) AS id_lra,
    COALESCE(bfi.id_bfi, -1) AS id_bfi,
    COALESCE(r.id_reservation, -1) AS id_reservation,
    COALESCE(ccp.id_ccp, -1) AS id_ccp,
    COALESCE(g.id_guarantee, -1) AS id_guarantee,
    COALESCE(g.id_charge, -1) AS id_guarantee_charge,
    (COALESCE(p.brl_entry_due_amount,0) + COALESCE(r.monthly_value,0) + COALESCE(ccp.value,0) + COALESCE(g.monthly_revenue,0)) AS due_monthly_revenue,
    (COALESCE(p.brl_entry_paid_amount,0) + COALESCE(r.monthly_value,0) + COALESCE(ccp.value,0) + COALESCE(g.monthly_revenue,0)) AS paid_monthly_revenue
FROM 
    contracts AS b
INNER JOIN 
    dw_public.dim_date AS dd
        ON dd.month_start BETWEEN DATE_TRUNC('month',b.dt_started) AND b.last_month_vigency
LEFT JOIN 
    payments AS p
        ON p.sk_contract = b.id_contract
        AND p.accrual_year_month = DATE_FORMAT(dd.month_start,'yyyyMM')
LEFT JOIN 
    mra
        ON mra.id_contract = b.id_contract
        AND p.accrual_year_month = DATE_FORMAT(mra.dt_reference,'yyyyMM')
LEFT JOIN
    bfi
        ON bfi.id_contract = p.sk_contract
        AND p.accrual_year_month = DATE_FORMAT(bfi.month_start,'yyyyMM')
LEFT JOIN
    lra
        ON lra.id_contract = b.id_contract
        AND p.accrual_year_month = DATE_FORMAT(ADD_MONTHS(DATE_TRUNC('month', lra.ts_expected_due), -1), 'yyyyMM')
LEFT JOIN
    lpf_rent
        ON lpf_rent.sk_contract = b.id_contract
        AND p.accrual_year_month = lpf_rent.accrual_year_month
LEFT JOIN
    lpf_condo
        ON lpf_condo.sk_contract = b.id_contract
        AND p.accrual_year_month = lpf_condo.accrual_year_month
LEFT JOIN
    reservation AS r
        ON r.id_contract = b.id_contract
        AND r.month_start = dd.month_start
LEFT JOIN
    ccp
        ON ccp.id_contract = b.id_contract
        AND ccp.accrual_year_month = DATE_FORMAT(dd.month_start,'yyyyMM')
LEFT JOIN
    guarantee AS g
        ON g.id_contract = b.id_contract
        AND g.accrual_year_month = DATE_FORMAT(dd.month_start,'yyyyMM')
WHERE
    (p.accrual_year_month IS NOT NULL OR r.id_reservation IS NOT NULL OR ccp.accrual_year_month IS NOT NULL OR g.accrual_year_month IS NOT NULL)