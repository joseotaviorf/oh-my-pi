WITH pipe_calendar AS (
    SELECT
        DATE_TRUNC('month', cwt.dt_reference) AS month,
        LAST_DAY(cwt.dt_reference) AS month_end,
        cwt.dt_pipe
    FROM
        dw_collections_segmentation.fact_contract_wallet_timeline AS cwt
    WHERE
        cwt.dt_reference >= DATE_TRUNC('month', CURRENT_DATE) - INTERVAL '5' MONTH
        AND (
            cwt.year > YEAR(DATE_TRUNC('month', CURRENT_DATE) - INTERVAL '5' MONTH)
            OR (
                cwt.year = YEAR(DATE_TRUNC('month', CURRENT_DATE) - INTERVAL '5' MONTH)
                AND cwt.month >= MONTH(DATE_TRUNC('month', CURRENT_DATE) - INTERVAL '5' MONTH)
            )
        )
    GROUP BY
        1,
        2,
        3
    UNION
    SELECT
        DATE_TRUNC('month', hardcoded_pipe.dt_pipe) AS month,
        LAST_DAY(hardcoded_pipe.dt_pipe) AS month_end,
        hardcoded_pipe.dt_pipe
    FROM (
        VALUES
            (DATE '2026-06-08'),
            (DATE '2026-07-07'),
            (DATE '2026-08-07'),
            (DATE '2026-09-08'),
            (DATE '2026-10-07'),
            (DATE '2026-11-09'),
            (DATE '2026-12-07')
    ) AS hardcoded_pipe(dt_pipe)
),
calendar_cardinal_points_ AS (
    SELECT
        month,
        month_end,
        dt_pipe,
        dt_pipe + INTERVAL '1' DAY AS dt_pipe_turn,
        LEAD(dt_pipe, 1) OVER (ORDER BY dt_pipe) AS next_pipe,
        LEAD(dt_pipe, 1) OVER (ORDER BY dt_pipe) + INTERVAL '1' DAY AS next_pipe_turn,
        LEAD(month_end, 1) OVER (ORDER BY month_end) AS next_eom
    FROM
        pipe_calendar
),
calendar_cardinal_points AS (
    SELECT
        ccp.month,
        ccp.month_end,
        ccp.dt_pipe,
        ccp.dt_pipe_turn,
        ccp.next_pipe,
        ccp.next_pipe_turn,
        ccp.next_eom
    FROM
        calendar_cardinal_points_ AS ccp
    WHERE
        ccp.dt_pipe <= (
            SELECT
                MIN(dt_pipe)
            FROM
                calendar_cardinal_points_
            WHERE
                dt_pipe > CURRENT_DATE
        )
),
pipe_period_calendar AS (
    SELECT
        ccp.dt_pipe_turn AS pipe_period_start,
        ccp.next_pipe AS pipe_period_end,
        ccp.dt_pipe,
        EXPLODE(SEQUENCE(ccp.dt_pipe_turn, ccp.next_pipe, INTERVAL 1 DAY)) AS dt_reference
    FROM
        calendar_cardinal_points AS ccp
    WHERE
        ccp.next_pipe IS NOT NULL
        AND ccp.dt_pipe_turn <= ccp.next_pipe
),
invoice_wallet_window AS (
    SELECT
        iwt.sk_invoice,
        iwt.sk_contract,
        iwt.dt_reference,
        iwt.due_amount,
        iwt.recovered_amount,
        iwt.invoice_delay_t2
    FROM
        dw_collections_segmentation.fact_invoice_wallet_timeline AS iwt
    WHERE
        iwt.dt_reference >= DATE_TRUNC('month', CURRENT_DATE) - INTERVAL '6' MONTHS
        AND (
            iwt.year > YEAR(DATE_TRUNC('month', CURRENT_DATE) - INTERVAL '6' MONTHS)
            OR (
                iwt.year = YEAR(DATE_TRUNC('month', CURRENT_DATE) - INTERVAL '6' MONTHS)
                AND iwt.month >= MONTH(DATE_TRUNC('month', CURRENT_DATE) - INTERVAL '6' MONTHS)
            )
        )
),
contract_wallet_window AS (
    SELECT
        cwt.sk_contract,
        cwt.dt_reference,
        cwt.dt_pipe
    FROM
        dw_collections_segmentation.fact_contract_wallet_timeline AS cwt
    WHERE
        cwt.dt_reference >= DATE_TRUNC('month', CURRENT_DATE) - INTERVAL '6' MONTHS
        AND (
            cwt.year > YEAR(DATE_TRUNC('month', CURRENT_DATE) - INTERVAL '6' MONTHS)
            OR (
                cwt.year = YEAR(DATE_TRUNC('month', CURRENT_DATE) - INTERVAL '6' MONTHS)
                AND cwt.month >= MONTH(DATE_TRUNC('month', CURRENT_DATE) - INTERVAL '6' MONTHS)
            )
        )
        AND cwt.wallet > 0
),
contract_features_normalized AS (
    SELECT
        cft.sk_contract,
        cft.dt_reference,
        cft.clustered_segmentation AS segmentation
    FROM
        dw_collections_segmentation.fact_contract_features_timeline AS cft
    WHERE
        cft.dt_reference >= DATE_TRUNC('month', CURRENT_DATE) - INTERVAL '6' MONTHS
        AND (
            cft.year > YEAR(DATE_TRUNC('month', CURRENT_DATE) - INTERVAL '6' MONTHS)
            OR (
                cft.year = YEAR(DATE_TRUNC('month', CURRENT_DATE) - INTERVAL '6' MONTHS)
                AND cft.month >= MONTH(DATE_TRUNC('month', CURRENT_DATE) - INTERVAL '6' MONTHS)
            )
        )
        AND cft.clustered_segmentation NOT IN ('active-current', 'ended-current')
),
invoice_pipe_boundaries AS (
    SELECT
        ppc.pipe_period_start,
        ppc.pipe_period_end,
        ppc.dt_pipe,
        cfn.segmentation,
        iwt.sk_invoice,
        FIRST(cwt.dt_pipe) AS dt_pipe_cwt,
        FIRST(iwt.sk_contract) AS sk_contract,
        MIN(iwt.dt_reference) AS dt_min_view,
        MAX(iwt.dt_reference) AS dt_max_view,
        MAX(iwt.due_amount) AS due_amount,
        MAX(iwt.recovered_amount) AS recovered_amount,
        MAX(iwt.invoice_delay_t2) AS invoice_delay_t2
    FROM
        invoice_wallet_window AS iwt
    INNER JOIN
        pipe_period_calendar AS ppc
            ON iwt.dt_reference = ppc.dt_reference
    INNER JOIN
        contract_wallet_window AS cwt
            ON cwt.dt_reference = iwt.dt_reference
            AND cwt.sk_contract = iwt.sk_contract
    INNER JOIN
        contract_features_normalized AS cfn
            ON cfn.dt_reference = iwt.dt_reference
            AND cfn.sk_contract = iwt.sk_contract
    GROUP BY 1, 2, 3, 4, 5
),
invoice_pipe_daily_spine AS (
    SELECT
        ipb.pipe_period_start,
        ipb.pipe_period_end,
        ipb.dt_pipe,
        ipb.segmentation,
        ipb.sk_invoice,
        ipb.dt_pipe_cwt,
        ipb.sk_contract,
        ipb.dt_min_view,
        ipb.dt_max_view,
        ipb.due_amount,
        ipb.recovered_amount,
        ipb.invoice_delay_t2,
        EXPLODE(
            SEQUENCE(
                GREATEST(ipb.dt_min_view, ipb.pipe_period_start),
                ipb.pipe_period_end,
                INTERVAL 1 DAY
            )
        ) AS dt_reference
    FROM
        invoice_pipe_boundaries AS ipb
    WHERE
        GREATEST(ipb.dt_min_view, ipb.pipe_period_start) <= ipb.pipe_period_end
),
daily_accumulation AS (
    SELECT
        ipds.dt_reference,
        ipds.segmentation AS segment,
        ipds.pipe_period_start,
        FIRST(ipds.dt_pipe_cwt) AS dt_pipe,
        COUNT(DISTINCT
            CASE
                WHEN COALESCE(cfn.segmentation, 'Unsegmented') = ipds.segmentation THEN iwt.sk_contract
            END
        ) AS n_contracts_at_reference,
        COUNT(DISTINCT ipds.sk_contract) AS n_contracts_acc,
        COUNT(DISTINCT
            CASE
                WHEN COALESCE(cfn.segmentation, 'Unsegmented') = ipds.segmentation
                 AND iwt.invoice_delay_t2 > 0 THEN iwt.sk_invoice
            END
        ) AS n_invoices_DT2_at_reference,
        COUNT(DISTINCT
            CASE
                WHEN ipds.dt_reference <= ipds.dt_max_view AND iwt.invoice_delay_t2 > 0 THEN iwt.sk_invoice
                WHEN ipds.dt_reference > ipds.dt_max_view AND ipds.invoice_delay_t2 > 0 THEN ipds.sk_invoice
            END
        ) AS n_invoices_DT2_acc,
        COUNT(DISTINCT
            CASE
                WHEN ipds.dt_reference <= ipds.dt_max_view
                 AND iwt.recovered_amount > 0 AND iwt.invoice_delay_t2 > 0 THEN iwt.sk_invoice
                WHEN ipds.dt_reference > ipds.dt_max_view
                 AND ipds.recovered_amount > 0 AND ipds.invoice_delay_t2 > 0 THEN ipds.sk_invoice
            END
        ) AS recovered_invoices_DT2_acc,
        SUM(
            CASE
                WHEN COALESCE(cfn.segmentation, 'Unsegmented') = ipds.segmentation
                 AND iwt.invoice_delay_t2 > 0 THEN ABS(ipds.due_amount)
            END
        ) AS due_amount_DT2_at_reference,
        SUM(
            CASE
                WHEN ipds.dt_reference <= ipds.dt_max_view AND iwt.invoice_delay_t2 > 0 THEN ABS(iwt.due_amount)
                WHEN ipds.dt_reference > ipds.dt_max_view AND ipds.invoice_delay_t2 > 0 THEN ABS(ipds.due_amount)
            END
        ) AS due_amount_DT2_acc,
        SUM(
            CASE
                WHEN ipds.dt_reference <= ipds.dt_max_view AND iwt.invoice_delay_t2 > 0 THEN iwt.recovered_amount
                WHEN ipds.dt_reference > ipds.dt_max_view AND ipds.invoice_delay_t2 > 0 THEN ipds.recovered_amount
            END
        ) AS recovered_amount_DT2_acc
    FROM
        invoice_pipe_daily_spine AS ipds
    LEFT JOIN
        invoice_wallet_window AS iwt
            ON iwt.dt_reference = ipds.dt_reference
            AND iwt.sk_invoice = ipds.sk_invoice
    LEFT JOIN
        contract_features_normalized AS cfn
            ON cfn.dt_reference = iwt.dt_reference
            AND cfn.sk_contract = iwt.sk_contract
    WHERE
        ipds.dt_reference >= DATE_TRUNC('month', CURRENT_DATE) - INTERVAL '6' MONTHS
        AND ipds.dt_reference <= CURRENT_DATE
    GROUP BY 1, 2, 3
),
business_day_context AS (
    SELECT
        da.segment,
        DATE_DIFF(da.dt_reference, da.pipe_period_start) + 1 AS days_to_pipe,
        COUNT(
            CASE
                WHEN da.dt_reference >= da.pipe_period_start
                 AND dd.is_brz_fintech_business_day THEN da.dt_reference
            END
        ) OVER (
            PARTITION BY da.segment, da.pipe_period_start
            ORDER BY da.dt_reference ASC
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) - 1 AS n_business_days_since_pipe,
        da.n_contracts_at_reference,
        da.n_contracts_acc,
        da.n_invoices_DT2_at_reference,
        da.n_invoices_DT2_acc,
        da.recovered_invoices_DT2_acc,
        da.due_amount_DT2_at_reference,
        da.due_amount_DT2_acc,
        da.recovered_amount_DT2_acc,
        COALESCE(
            da.recovered_amount_DT2_acc / NULLIF(da.due_amount_DT2_acc, 0),
            0
        ) AS recovery_rate_amount_t2,
        dd.is_brz_fintech_business_day,
        dd.next_brz_fintech_business_day,
        da.pipe_period_start AS dt_pipe_period_start,
        da.dt_pipe,
        da.dt_reference
    FROM
        daily_accumulation AS da
    LEFT JOIN
        dw_public.dim_date AS dd
            ON dd.date = da.dt_reference
),
final_ordering AS (
    SELECT
        bdc.segment,
        ROW_NUMBER() OVER (
            PARTITION BY bdc.n_business_days_since_pipe, bdc.dt_pipe_period_start, bdc.segment
            ORDER BY bdc.dt_reference DESC
        ) AS rn_business_day,
        bdc.n_business_days_since_pipe,
        bdc.days_to_pipe,
        bdc.n_contracts_at_reference,
        bdc.n_contracts_acc,
        bdc.n_invoices_DT2_at_reference,
        bdc.n_invoices_DT2_acc,
        bdc.recovered_invoices_DT2_acc,
        bdc.due_amount_DT2_at_reference,
        bdc.due_amount_DT2_acc,
        bdc.recovered_amount_DT2_acc,
        bdc.recovery_rate_amount_t2,
        bdc.is_brz_fintech_business_day,
        bdc.next_brz_fintech_business_day,
        bdc.dt_pipe_period_start,
        bdc.dt_pipe,
        bdc.dt_reference
    FROM
        business_day_context AS bdc
)
SELECT
    segment,
    rn_business_day,
    n_business_days_since_pipe,
    days_to_pipe,
    n_contracts_at_reference,
    n_contracts_acc,
    n_invoices_DT2_at_reference,
    n_invoices_DT2_acc,
    recovered_invoices_DT2_acc,
    due_amount_DT2_at_reference,
    due_amount_DT2_acc,
    recovered_amount_DT2_acc,
    recovery_rate_amount_t2,
    is_brz_fintech_business_day,
    next_brz_fintech_business_day,
    dt_pipe_period_start,
    dt_pipe,
    dt_reference,
    NOW() AS ts_load
FROM
    final_ordering
WHERE
    segment IS NOT NULL
