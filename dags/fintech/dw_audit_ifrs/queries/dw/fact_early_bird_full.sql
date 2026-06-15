WITH
hist_contract_write_off AS (
    SELECT DISTINCT
        cont.sk_contract AS id_contract
    FROM
        dw_payment_snapshot.dim_invoice_snapshot AS snap
    LEFT JOIN
        datalake_retsuko.invoice AS inv
            ON inv.id_external = snap.sk_invoice
    LEFT JOIN
        dw_public_snapshot.dim_contract_snapshot AS cont
            ON cont.sk_contract = inv.id_contract_external
            AND cont.year = snap.year
            AND cont.month = snap.month
            AND cont.day = snap.day
    WHERE
        snap.is_write_off IS TRUE
        OR snap.reason IN ('write-off-negotiation-cyber', 'write-off-negotiation-5a')
),
hist_invoice_snapshot_raw AS (
    SELECT
        ps.sk_invoice,
        ps.frequency,
        ps.payment_status,
        ps.user,
        CASE
            WHEN ps.reason IN ('write-off-negotiation-cyber', 'write-off-negotiation-5a') THEN TRUE
            ELSE COALESCE(ps.is_write_off, FALSE)
        END AS is_write_off,
        ps.due_amount,
        ps.paid_amount,
        ps.accrual_year_month,
        ps.ts_created,
        ps.ts_canceled,
        ps.dt_sent,
        ps.dt_due,
        COALESCE(
            ps.dt_due_adjusted,
            IF(dd.is_brz_fintech_business_day, ps.dt_due, dd.next_brz_fintech_business_day)
        ) AS dt_due_adjusted_retsuko,
        ps.dt_paid,
        CASE
            WHEN ps.dt_write_off IS NULL
                AND ps.reason IN ('write-off-negotiation-cyber', 'write-off-negotiation-5a')
                THEN DATE(ps.ts_created)
            ELSE ps.dt_write_off
        END AS dt_write_off,
        ps.year,
        ps.month,
        ps.day,
        ps.ts_snapshot,
        dt.month_end AS closing_day,
        CAST(ps.ts_snapshot AS DATE) AS dt_snapshot
    FROM
        dw_payment_snapshot.dim_invoice_snapshot AS ps
    LEFT JOIN
        dw_public.dim_date AS dt
            ON dt.sk_date = CAST(DATE_FORMAT(DATEADD(MONTH, -1, ps.ts_snapshot), 'yyyyMMdd') AS BIGINT)
    LEFT JOIN
        dw_public.dim_date AS dd
            ON dd.sk_date = CAST(DATE_FORMAT(DATE(ps.dt_due), 'yyyyMMdd') AS BIGINT)
    LEFT JOIN
        datalake_retsuko.invoice AS inv
            ON inv.id_external = ps.sk_invoice
    WHERE
        ps.due_amount <= 0
        AND ps.year = 2022
        AND ps.month = 10
),
dt_closing_pre_snapshot AS (
    SELECT DISTINCT
        dt_closing AS dt_closing_before_snapshots
    FROM
        dw_losses.fact_closing
    WHERE
        dt_closing >= DATE('2018-09-01')
        AND dt_closing < DATE('2022-07-01')
),
hist_total_base AS (
    SELECT
        d.dt_closing_before_snapshots AS dt_closing,
        bi.sk_invoice,
        bi.frequency,
        bi.payment_status,
        bi.user,
        bi.is_write_off,
        bi.due_amount,
        bi.paid_amount,
        bi.accrual_year_month,
        bi.ts_created,
        bi.ts_canceled,
        bi.dt_sent,
        bi.dt_due,
        bi.dt_due_adjusted_retsuko,
        bi.dt_paid,
        bi.dt_write_off,
        bi.year,
        bi.month,
        bi.day,
        bi.ts_snapshot,
        bi.closing_day,
        bi.dt_snapshot
    FROM
        dt_closing_pre_snapshot AS d
    CROSS JOIN
        hist_invoice_snapshot_raw AS bi
),
hist_invoice_snapshot_clean AS (
    SELECT
        dt_closing,
        sk_invoice,
        frequency,
        payment_status,
        user,
        is_write_off,
        due_amount,
        paid_amount,
        accrual_year_month,
        ts_created,
        ts_canceled,
        dt_sent,
        dt_due,
        dt_due_adjusted_retsuko,
        dt_paid,
        dt_write_off,
        year,
        month,
        day,
        ts_snapshot,
        closing_day,
        dt_snapshot
    FROM
        hist_total_base
    WHERE
        DATE(ts_created) <= dt_closing
        AND (DATE(dt_paid) IS NULL OR DATE_TRUNC('month', dt_paid) >= DATE_TRUNC('month', dt_closing))
        AND (DATE(ts_canceled) IS NULL OR DATE(ts_canceled) >= dt_closing)
        AND payment_status NOT IN ('not payable')
),
hist_contract_info AS (
    SELECT DISTINCT
        dpdc.sk_contract AS id_contract,
        dpdc.dt_start AS dt_started,
        dpdc.dt_annulment AS dt_termination,
        CAST(dpdc.ts_analyst_annulment_input AS DATE) AS annulment_input_dt,
        CASE
            WHEN UPPER(dpdc.guarantee) IN (
                'RENTALDEPOSIT', 'RENTALGUARANTEE', 'DEPOSITO',
                'PRO_GUARANTOR', 'THIRDPARTYGUARANTEE', 'STANDALONE'
            ) THEN TRUE
            ELSE FALSE
        END AS guarantee_type,
        dpdc.country_code <> 'BR' AS flag_is_international,
        (dpdc.dt_annulment IS NOT NULL AND DATEDIFF(dpdc.dt_annulment, dpdc.dt_start) <= 0) AS flag_is_before_started_raw,
        CASE
            WHEN UPPER(dpdc.guarantee) = 'SEGUROFAIRFAX' THEN 'Fairfax'
            WHEN UPPER(dpdc.guarantee) = 'PRO_GUARANTOR' THEN 'Pro_Guarantor'
            WHEN UPPER(dpdc.guarantee) = 'RENTALGUARANTEE' THEN 'Rental_Guarantee'
            WHEN UPPER(dpdc.guarantee) IN ('RENTALDEPOSIT', 'DEPOSITO') THEN 'Rental_Deposit'
            WHEN UPPER(dpdc.guarantee) = 'STANDALONE' THEN 'Standalone'
            WHEN UPPER(dpdc.guarantee) = 'THIRDPARTYGUARANTEE' THEN 'Third_Party_3D'
            ELSE 'Outros'
        END AS contract_guarantee,
        COALESCE(DATE(dpdc.ts_signature), DATE(dpdc.dt_start)) AS contract_signature_date,
        dpdc.dt_annulment,
        dpdc.year,
        dpdc.month,
        dpdc.day
    FROM
        dw_public_snapshot.dim_contract_snapshot AS dpdc
    WHERE
        dpdc.sk_contract <> -1
),
hist_contract_aux AS (
    SELECT
        id_contract,
        dt_started,
        dt_termination,
        annulment_input_dt,
        guarantee_type,
        flag_is_international,
        flag_is_before_started_raw,
        contract_guarantee,
        contract_signature_date,
        dt_annulment,
        year,
        month,
        day
    FROM
        hist_contract_info
    WHERE
        year = 2022
        AND month = 10
        AND day = 4
),
hist_repair_offboarding AS (
    SELECT DISTINCT
        id_invoice,
        dt_closing
    FROM
        datalake_losses.bill_items
    WHERE
        bill_item_name = 'repair offboarding'
),
hist_closing_draft AS (
    SELECT
        m.dt_closing,
        m.sk_invoice,
        m.frequency,
        m.payment_status,
        m.user,
        m.is_write_off,
        m.due_amount,
        m.paid_amount,
        m.accrual_year_month,
        m.ts_created,
        m.ts_canceled,
        m.dt_sent,
        m.dt_due,
        m.dt_due_adjusted_retsuko,
        m.dt_paid,
        m.dt_write_off,
        m.year,
        m.month,
        m.day,
        m.ts_snapshot,
        m.closing_day,
        m.dt_snapshot,
        CASE
            WHEN m.ts_canceled IS NOT NULL
                AND m.ts_canceled > m.dt_closing
                AND m.ts_canceled <= m.ts_snapshot THEN TRUE
            ELSE FALSE
        END AS flag_canceled_in_dead_time,
        CASE
            WHEN m.payment_status = 'written down'
                AND m.dt_paid > m.dt_closing
                AND m.dt_paid <= m.ts_snapshot THEN TRUE
            ELSE FALSE
        END AS flag_writtendown_in_dead_time,
        m.dt_paid = m.dt_closing AS flag_paid_in_closing_day,
        cwo.id_contract IS NOT NULL AS is_contract_write_off,
        COALESCE(c.flag_is_before_started_raw, c_bkp.flag_is_before_started_raw) AS flag_is_before_started,
        COALESCE(c.id_contract, c_bkp.id_contract) AS id_contract,
        COALESCE(c.dt_started, c_bkp.dt_started) AS dt_started,
        COALESCE(c.dt_termination, c_bkp.dt_termination) AS dt_termination,
        COALESCE(c.annulment_input_dt, c_bkp.annulment_input_dt) AS annulment_input_dt,
        COALESCE(c.guarantee_type, c_bkp.guarantee_type) AS guarantee_type,
        COALESCE(c.flag_is_international, c_bkp.flag_is_international) AS flag_is_international,
        COALESCE(c.flag_is_before_started_raw, c_bkp.flag_is_before_started_raw) AS flag_is_before_started_raw,
        b.id_invoice IS NOT NULL AS has_repair_offboarding_bill_item,
        CASE
            WHEN COALESCE(c.dt_annulment, CURRENT_DATE()) <= m.dt_closing THEN 'Finalizado'
            ELSE 'Ativo'
        END AS status_mes_fechamento,
        cr.city,
        c.contract_signature_date,
        c.contract_guarantee,
        c.dt_annulment
    FROM
        hist_invoice_snapshot_clean AS m
    LEFT JOIN
        datalake_retsuko.invoice AS inv
            ON inv.id_external = m.sk_invoice
    LEFT JOIN
        datalake_retsuko_clean.contract AS cr
            ON cr.id = inv.id_contract
    LEFT JOIN
        hist_contract_info AS c
            ON c.id_contract = cr.id_external
            AND c.year = m.year
            AND c.month = m.month
            AND c.day = m.day
    LEFT JOIN
        hist_contract_aux AS c_bkp
            ON c_bkp.id_contract = cr.id_external
    LEFT JOIN
        hist_repair_offboarding AS b
            ON b.id_invoice = m.sk_invoice
            AND b.dt_closing = m.closing_day
    LEFT JOIN
        hist_contract_write_off AS cwo
            ON cwo.id_contract = COALESCE(c.id_contract, c_bkp.id_contract)
),
hist_rebuild AS (
    SELECT
        dt_closing,
        sk_invoice AS id_invoice,
        id_contract,
        accrual_year_month,
        status_mes_fechamento AS closing_month_status,
        due_amount,
        frequency,
        CASE
            WHEN frequency = 'monthly' THEN 'Mensal'
            WHEN frequency = 'onboarding' THEN 'Onboarding'
            WHEN frequency = 'extra' THEN 'Extra'
            WHEN frequency = 'early termination' THEN 'Rescisão'
            WHEN frequency = 'pos rental' THEN 'Pos_rental'
            ELSE frequency
        END AS invoice_type,
        city,
        contract_guarantee,
        guarantee_type AS is_guarantee_paid,
        flag_is_before_started AS is_before_started,
        flag_is_before_started_raw AS is_before_started_raw,
        flag_canceled_in_dead_time AS is_canceled_in_dead_time,
        flag_is_international AS is_international,
        flag_paid_in_closing_day AS is_paid_in_closing_day,
        flag_writtendown_in_dead_time AS is_writtendown_in_dead_time,
        is_write_off,
        is_contract_write_off,
        has_repair_offboarding_bill_item,
        paid_amount,
        payment_status,
        CASE
            WHEN payment_status = 'paid' AND dt_paid > dt_closing THEN 'open'
            WHEN payment_status = 'written down' AND dt_paid > dt_closing THEN 'open'
            WHEN payment_status = 'paid' AND dt_paid <= dt_closing THEN 'paid'
            WHEN payment_status = 'written down' AND dt_paid <= dt_closing THEN 'written down'
            WHEN payment_status = 'canceled' AND DATE(ts_canceled) > dt_closing THEN 'open'
            WHEN payment_status = 'canceled' AND DATE(ts_canceled) <= dt_closing THEN 'canceled'
            ELSE payment_status
        END AS payment_status_timeline,
        COALESCE(user, 'tenant') AS user,
        'HISTORICAL REBUILD' AS origin_factor,
        DATE(ts_created) AS dt_created,
        DATE(ts_canceled) AS dt_canceled,
        closing_day AS dt_closing_source_photo,
        contract_signature_date AS dt_contract_signature,
        dt_annulment,
        dt_due,
        dt_due_adjusted_retsuko,
        dt_paid,
        CASE
            WHEN payment_status = 'paid' AND dt_paid > dt_closing THEN NULL
            WHEN payment_status = 'written down' AND dt_paid > dt_closing THEN NULL
            WHEN payment_status IN ('paid', 'written down') AND dt_paid <= dt_closing THEN dt_paid
            ELSE dt_paid
        END AS dt_paid_timeline,
        dt_sent,
        dt_write_off,
        dt_snapshot
    FROM
        hist_closing_draft
    WHERE
        CASE
            WHEN payment_status = 'paid' AND dt_paid > dt_closing THEN 'open'
            WHEN payment_status = 'written down' AND dt_paid > dt_closing THEN 'open'
            WHEN payment_status = 'paid' AND dt_paid <= dt_closing THEN 'paid'
            WHEN payment_status = 'written down' AND dt_paid <= dt_closing THEN 'written down'
            WHEN payment_status = 'canceled' AND DATE(ts_canceled) > dt_closing THEN 'open'
            WHEN payment_status = 'canceled' AND DATE(ts_canceled) <= dt_closing THEN 'canceled'
            ELSE payment_status
        END = 'paid'
        AND COALESCE(user, 'tenant') = 'tenant'
        AND frequency IN ('monthly', 'onboarding')
        AND DATE_TRUNC('month', CASE
            WHEN payment_status = 'paid' AND dt_paid > dt_closing THEN NULL
            WHEN payment_status = 'written down' AND dt_paid > dt_closing THEN NULL
            WHEN payment_status IN ('paid', 'written down') AND dt_paid <= dt_closing THEN dt_paid
            ELSE dt_paid
        END) = DATE_TRUNC('month', dt_closing)
        AND DATE_TRUNC('month', DATE(ts_created)) = DATE_TRUNC('month', dt_closing)
),
-- ============================================================
-- SNAPSHOT (Aug/2022 onwards)
-- ============================================================
snap_contract_write_off AS (
    SELECT DISTINCT
        cont.sk_contract AS id_contract
    FROM
        dw_payment_snapshot.dim_invoice_snapshot AS snap
    LEFT JOIN
        datalake_retsuko.invoice AS inv
            ON inv.id_external = snap.sk_invoice
    LEFT JOIN
        dw_public_snapshot.dim_contract_snapshot AS cont
            ON cont.sk_contract = inv.id_contract_external
            AND cont.year = snap.year
            AND cont.month = snap.month
            AND cont.day = snap.day
    WHERE
        snap.is_write_off IS TRUE
        OR snap.reason IN ('write-off-negotiation-cyber', 'write-off-negotiation-5a')
),
snap_invoice_snapshot_raw AS (
    SELECT
        ps.sk_invoice,
        ps.frequency,
        ps.payment_status,
        ps.user,
        CASE
            WHEN ps.reason IN ('write-off-negotiation-cyber', 'write-off-negotiation-5a') THEN TRUE
            ELSE COALESCE(ps.is_write_off, FALSE)
        END AS is_write_off,
        ps.due_amount,
        ps.paid_amount,
        ps.accrual_year_month,
        ps.ts_created,
        ps.ts_canceled,
        ps.dt_sent,
        ps.dt_due,
        COALESCE(
            ps.dt_due_adjusted,
            IF(dd.is_brz_fintech_business_day, ps.dt_due, dd.next_brz_fintech_business_day)
        ) AS dt_due_adjusted_retsuko,
        ps.dt_paid,
        CASE
            WHEN ps.dt_write_off IS NULL
                AND ps.reason IN ('write-off-negotiation-cyber', 'write-off-negotiation-5a')
                THEN DATE(ps.ts_created)
            ELSE ps.dt_write_off
        END AS dt_write_off,
        ps.year,
        ps.month,
        ps.day,
        ps.ts_snapshot,
        dt.month_end AS closing_day,
        CAST(ps.ts_snapshot AS DATE) AS dt_snapshot
    FROM
        dw_payment_snapshot.dim_invoice_snapshot AS ps
    LEFT JOIN
        dw_public.dim_date AS dt
            ON dt.sk_date = CAST(DATE_FORMAT(DATEADD(MONTH, -1, ps.ts_snapshot), 'yyyyMMdd') AS BIGINT)
    LEFT JOIN
        dw_public.dim_date AS dd
            ON dd.sk_date = CAST(DATE_FORMAT(DATE(ps.dt_due), 'yyyyMMdd') AS BIGINT)
    LEFT JOIN
        datalake_retsuko.invoice AS inv
            ON inv.id_external = ps.sk_invoice
    WHERE
        ps.due_amount <= 0
        AND ((ps.year = 2022 AND ps.month > 7) OR ps.year > 2022)
),
snap_invoice_snapshot_clean AS (
    SELECT
        sk_invoice,
        frequency,
        payment_status,
        user,
        is_write_off,
        due_amount,
        paid_amount,
        accrual_year_month,
        ts_created,
        ts_canceled,
        dt_sent,
        dt_due,
        dt_due_adjusted_retsuko,
        dt_paid,
        dt_write_off,
        year,
        month,
        day,
        ts_snapshot,
        closing_day,
        dt_snapshot
    FROM
        snap_invoice_snapshot_raw
    WHERE
        CAST(ts_created AS DATE) <= closing_day
        AND payment_status NOT IN ('not payable')
        AND DATE_TRUNC('month', dt_paid) = DATE_TRUNC('month', closing_day)
        AND DATE_TRUNC('month', ts_created) = DATE_TRUNC('month', closing_day)
        AND frequency IN ('monthly', 'onboarding')
        AND user = 'tenant'
        AND payment_status = 'paid'
),
snap_contract_info AS (
    SELECT DISTINCT
        dpdc.sk_contract AS id_contract,
        dpdc.dt_start AS dt_started,
        dpdc.dt_annulment AS dt_termination,
        CAST(dpdc.ts_analyst_annulment_input AS DATE) AS annulment_input_dt,
        CASE
            WHEN UPPER(dpdc.guarantee) IN (
                'RENTALDEPOSIT', 'RENTALGUARANTEE', 'DEPOSITO',
                'PRO_GUARANTOR', 'THIRDPARTYGUARANTEE', 'STANDALONE'
            ) THEN TRUE
            ELSE FALSE
        END AS guarantee_type,
        dpdc.country_code <> 'BR' AS flag_is_international,
        (dpdc.dt_annulment IS NOT NULL AND DATEDIFF(dpdc.dt_annulment, dpdc.dt_start) <= 0) AS flag_is_before_started_raw,
        CASE
            WHEN UPPER(dpdc.guarantee) = 'SEGUROFAIRFAX' THEN 'Fairfax'
            WHEN UPPER(dpdc.guarantee) = 'PRO_GUARANTOR' THEN 'Pro_Guarantor'
            WHEN UPPER(dpdc.guarantee) = 'RENTALGUARANTEE' THEN 'Rental_Guarantee'
            WHEN UPPER(dpdc.guarantee) IN ('RENTALDEPOSIT', 'DEPOSITO') THEN 'Rental_Deposit'
            WHEN UPPER(dpdc.guarantee) = 'STANDALONE' THEN 'Standalone'
            WHEN UPPER(dpdc.guarantee) = 'THIRDPARTYGUARANTEE' THEN 'Third_Party_3D'
            ELSE 'Outros'
        END AS contract_guarantee,
        COALESCE(DATE(dpdc.ts_signature), DATE(dpdc.dt_start)) AS contract_signature_date,
        dpdc.dt_annulment,
        dpdc.year,
        dpdc.month,
        dpdc.day
    FROM
        dw_public_snapshot.dim_contract_snapshot AS dpdc
    WHERE
        dpdc.sk_contract <> -1
),
snap_contract_aux AS (
    SELECT
        id_contract,
        dt_started,
        dt_termination,
        annulment_input_dt,
        guarantee_type,
        flag_is_international,
        flag_is_before_started_raw,
        contract_guarantee,
        contract_signature_date,
        dt_annulment,
        year,
        month,
        day
    FROM
        snap_contract_info
    WHERE
        year = 2022
        AND month = 10
        AND day = 4
),
snap_repair_offboarding AS (
    SELECT DISTINCT
        id_invoice,
        dt_closing
    FROM
        datalake_losses.bill_items
    WHERE
        bill_item_name = 'repair offboarding'
),
snap_closing_draft AS (
    SELECT
        m.sk_invoice,
        m.frequency,
        m.payment_status,
        m.user,
        m.is_write_off,
        m.due_amount,
        m.paid_amount,
        m.accrual_year_month,
        m.ts_created,
        m.ts_canceled,
        m.dt_sent,
        m.dt_due,
        m.dt_due_adjusted_retsuko,
        m.dt_paid,
        m.dt_write_off,
        m.year,
        m.month,
        m.day,
        m.ts_snapshot,
        m.closing_day,
        m.dt_snapshot,
        CASE
            WHEN m.ts_canceled IS NOT NULL
                AND m.ts_canceled > m.closing_day
                AND m.ts_canceled <= m.ts_snapshot THEN TRUE
            ELSE FALSE
        END AS flag_canceled_in_dead_time,
        CASE
            WHEN m.payment_status = 'written down'
                AND m.dt_paid > m.closing_day
                AND m.dt_paid <= m.ts_snapshot THEN TRUE
            ELSE FALSE
        END AS flag_writtendown_in_dead_time,
        m.dt_paid = m.closing_day AS flag_paid_in_closing_day,
        cwo.id_contract IS NOT NULL AS is_contract_write_off,
        COALESCE(c.flag_is_before_started_raw, c_bkp.flag_is_before_started_raw) AS flag_is_before_started,
        COALESCE(c.id_contract, c_bkp.id_contract) AS id_contract,
        COALESCE(c.dt_started, c_bkp.dt_started) AS dt_started,
        COALESCE(c.dt_termination, c_bkp.dt_termination) AS dt_termination,
        COALESCE(c.annulment_input_dt, c_bkp.annulment_input_dt) AS annulment_input_dt,
        COALESCE(c.guarantee_type, c_bkp.guarantee_type) AS guarantee_type,
        COALESCE(c.flag_is_international, c_bkp.flag_is_international) AS flag_is_international,
        COALESCE(c.flag_is_before_started_raw, c_bkp.flag_is_before_started_raw) AS flag_is_before_started_raw,
        b.id_invoice IS NOT NULL AS has_repair_offboarding_bill_item,
        CASE
            WHEN COALESCE(c.dt_annulment, CURRENT_DATE()) <= (DATE_TRUNC('month', m.dt_snapshot) - INTERVAL '1' DAY)
                THEN 'Finalizado'
            ELSE 'Ativo'
        END AS status_mes_fechamento,
        cr.city,
        c.contract_signature_date,
        c.contract_guarantee,
        c.dt_annulment
    FROM
        snap_invoice_snapshot_clean AS m
    LEFT JOIN
        datalake_retsuko.invoice AS inv
            ON inv.id_external = m.sk_invoice
    LEFT JOIN
        datalake_retsuko_clean.contract AS cr
            ON cr.id = inv.id_contract
    LEFT JOIN
        snap_contract_info AS c
            ON c.id_contract = cr.id_external
            AND c.year = m.year
            AND c.month = m.month
            AND c.day = m.day
    LEFT JOIN
        snap_contract_aux AS c_bkp
            ON c_bkp.id_contract = cr.id_external
    LEFT JOIN
        snap_repair_offboarding AS b
            ON b.id_invoice = m.sk_invoice
            AND b.dt_closing = m.closing_day
    LEFT JOIN
        snap_contract_write_off AS cwo
            ON cwo.id_contract = COALESCE(c.id_contract, c_bkp.id_contract)
)
SELECT
    closing_day AS dt_closing,
    sk_invoice AS id_invoice,
    id_contract,
    accrual_year_month,
    status_mes_fechamento AS closing_month_status,
    due_amount,
    frequency,
    CASE
        WHEN frequency = 'monthly' THEN 'Mensal'
        WHEN frequency = 'onboarding' THEN 'Onboarding'
        WHEN frequency = 'extra' THEN 'Extra'
        WHEN frequency = 'early termination' THEN 'Rescisão'
        WHEN frequency = 'pos rental' THEN 'Pos_rental'
        ELSE frequency
    END AS invoice_type,
    city,
    contract_guarantee,
    guarantee_type AS is_guarantee_paid,
    flag_is_before_started AS is_before_started,
    flag_is_before_started_raw AS is_before_started_raw,
    flag_canceled_in_dead_time AS is_canceled_in_dead_time,
    flag_is_international AS is_international,
    flag_paid_in_closing_day AS is_paid_in_closing_day,
    flag_writtendown_in_dead_time AS is_writtendown_in_dead_time,
    is_write_off,
    is_contract_write_off,
    has_repair_offboarding_bill_item,
    paid_amount,
    payment_status,
    payment_status AS payment_status_timeline,
    COALESCE(user, 'tenant') AS user,
    'SNAPSHOT' AS origin_factor,
    DATE(ts_created) AS dt_created,
    DATE(ts_canceled) AS dt_canceled,
    closing_day AS dt_closing_source_photo,
    contract_signature_date AS dt_contract_signature,
    dt_annulment,
    dt_due,
    dt_due_adjusted_retsuko,
    dt_paid,
    dt_paid AS dt_paid_timeline,
    dt_sent,
    dt_write_off,
    dt_snapshot
FROM
    snap_closing_draft

UNION ALL

SELECT
    dt_closing,
    id_invoice,
    id_contract,
    accrual_year_month,
    closing_month_status,
    due_amount,
    frequency,
    invoice_type,
    city,
    contract_guarantee,
    is_guarantee_paid,
    is_before_started,
    is_before_started_raw,
    is_canceled_in_dead_time,
    is_international,
    is_paid_in_closing_day,
    is_writtendown_in_dead_time,
    is_write_off,
    is_contract_write_off,
    has_repair_offboarding_bill_item,
    paid_amount,
    payment_status,
    payment_status_timeline,
    user,
    origin_factor,
    dt_created,
    dt_canceled,
    dt_closing_source_photo,
    dt_contract_signature,
    dt_annulment,
    dt_due,
    dt_due_adjusted_retsuko,
    dt_paid,
    dt_paid_timeline,
    dt_sent,
    dt_write_off,
    dt_snapshot
FROM
    hist_rebuild
