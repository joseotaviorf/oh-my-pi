SELECT
    id,
    company             AS id_company,
    boleto              AS id_bill,
    status,
    rev,
    revend              AS rev_end,
    revtype             AS rev_type,
    accrual_year,
    accrual_month,
    total_amount,
    created_at_mod      AS mod_created_at,
    company_mod         AS mod_company,
    accrual_year_mod    AS mod_accural_year,
    accrual_month_mod   AS mod_accrual_month,
    total_amount_mod    AS mod_total_amount,
    status_mod          AS mod_status,
    boleto_mod          AS mod_bill,
    due_date_mod        AS mod_due_date,
    due_date            AS dt_due,
    created_at          AS ts_created
FROM
    datalake_rental_guarantee_platform_raw.billing_report_aud
