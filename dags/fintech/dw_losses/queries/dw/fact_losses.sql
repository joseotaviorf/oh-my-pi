WITH
base_of_calculation AS (
    SELECT
        fp.sk_contract,
        fp.sk_invoice,
        fp.invoice_account_type,
        fp.payment_status,
        fp.invoice_status,
        fc.invoice_type,
        fc.closing_month_status AS contract_closing_month_status,
        fp.is_before_started,
        fp.is_international,
        fp.is_writtendown_in_dead_time,
        fp.is_contract_write_off,
        fp.has_repair_offboarding_bill_item,
        fc.city,
        CASE
            WHEN fp.risk_type = 'LR' THEN 'a.Low_Risk'
            WHEN fp.risk_type = 'HR' THEN 'b.High_Risk'
        END AS risk_group,
        CASE
            WHEN fc.is_guarantee_paid = false THEN 'c.Free'
            WHEN fc.is_guarantee_paid = true THEN 'd.Paid'
        END AS guarantee_group,
        CASE
            WHEN fp.dt_closing BETWEEN DATE('2021-12-31') AND DATE('2022-11-30') AND fp.risk_type = 'LR' THEN 'a.Low_Risk'
            WHEN fp.dt_closing BETWEEN DATE('2021-12-31') AND DATE('2022-11-30') AND fp.risk_type = 'HR' THEN 'b.High_Risk'
            WHEN fp.dt_closing >= DATE('2022-12-31') AND fc.is_guarantee_paid = false THEN 'c.Free'
            WHEN fp.dt_closing >= DATE('2022-12-31') AND fc.is_guarantee_paid = true THEN 'd.Paid'
            ELSE ''
        END AS provisional_group,
        fp.delay_contamined_range AS delay_contaminated_range,
        fp.provision_factor,
        ABS(fp.provision_balance) AS provision_balance,
        ABS(fp.due_amount) AS due_amount,
        DATE(DATE_TRUNC('month',fp.dt_closing)) AS dt_cohort,
        fp.dt_due_adjs AS dt_due_invoice_adjusted,
        fc.dt_contract_signature,
        fc.dt_annulment AS dt_contract_annulment,
        fp.dt_closing,
        fp.dt_snapshot,
        fp.dt_paid_adjs AS dt_paid_invoice_adjusted
    FROM
        dw_losses.fact_provision AS fp
    LEFT JOIN
       dw_losses.fact_closing AS fc
            ON fp.sk_invoice = fc.sk_invoice
                AND fp.sk_contract = fc.sk_contract
                AND fp.dt_closing = fc.dt_closing
    WHERE
        fp.is_international IS FALSE
        AND fp.is_before_started IS FALSE
        AND fp.payment_status <> 'written down'
        AND fp.is_write_off IS NOT TRUE
        AND NOT(fp.dt_closing >= DATE('2024-02-01') AND fp.has_repair_offboarding_bill_item)
),
monthly_aggregation AS (
    SELECT
        dt_cohort,
        SUM(provision_balance) AS provision_balance_monthly
    FROM base_of_calculation
    GROUP BY dt_cohort
),
monthly_lagged AS (
    SELECT
        dt_cohort,
        provision_balance_monthly,
        LAG(provision_balance_monthly, 1) OVER (
            ORDER BY dt_cohort ASC
        ) AS previous_month_provision_balance_monthly
    FROM monthly_aggregation
),
calculate_previous_pdd AS (
    SELECT
        f.sk_contract,
        f.sk_invoice,
        f.invoice_account_type,
        f.payment_status,
        f.invoice_status,
        f.invoice_type,
        f.contract_closing_month_status,
        f.is_before_started,
        f.is_international,
        f.is_writtendown_in_dead_time,
        f.is_contract_write_off,
        f.has_repair_offboarding_bill_item,
        f.city,
        f.risk_group,
        f.guarantee_group,
        f.provisional_group,
        f.delay_contaminated_range,
        f.provision_factor,
        f.provision_balance,
        (f.provision_balance / m.provision_balance_monthly) * m.previous_month_provision_balance_monthly AS previous_month_provision_balance,
        f.due_amount,
        f.dt_cohort,
        f.dt_closing,
        f.dt_snapshot,
        f.dt_due_invoice_adjusted,
        f.dt_paid_invoice_adjusted,
        f.dt_contract_signature,
        f.dt_contract_annulment
    FROM
        base_of_calculation AS f
    LEFT JOIN
        monthly_lagged AS m
            ON f.dt_cohort = m.dt_cohort
    WHERE m.provision_balance_monthly > 0
)
SELECT
    sk_contract,
    sk_invoice,
    invoice_account_type,
    payment_status,
    invoice_status,
    invoice_type,
    contract_closing_month_status,
    is_before_started,
    is_international,
    is_writtendown_in_dead_time,
    is_contract_write_off,
    has_repair_offboarding_bill_item,
    city,
    risk_group,
    guarantee_group,
    provisional_group,
    delay_contaminated_range,
    provision_factor,
    CAST(provision_balance AS DECIMAL(32,10)) AS provision_balance,
    CAST(provision_balance - previous_month_provision_balance AS DECIMAL(32,10)) AS losses,
    CAST(due_amount AS DECIMAL(32,10)) AS due_amount,
    dt_cohort,
    dt_closing,
    dt_snapshot,
    dt_due_invoice_adjusted,
    dt_paid_invoice_adjusted,
    dt_contract_signature,
    dt_contract_annulment,
    NOW() AS ts_load
FROM calculate_previous_pdd
