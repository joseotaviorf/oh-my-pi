SELECT
    id,
    bank_payment_id         AS id_bank_payment,
    agreement_id            AS id_agreement,
    billing_type,
    status,
    source_system,
    payment_code,
    rev,
    revend                  AS rev_end,
    revtype                 AS rev_type,
    version,
    value,
    paid_value,
    value_mod               AS mod_value,
    paid_value_mod          AS mod_paid_value,
    due_date_mod            AS mod_due_date,
    paid_date_mod           AS mod_paid_date,
    billing_type_mod        AS mod_billing_type,
    status_mod              AS mod_statua,
    agreement_mod           AS mod_agreement,
    source_system_mod       AS mod_source_system,
    bank_payment_id_mod     AS mod_id_bank_payment,
    payment_code_mod        AS mod_payment_code,
    due_date                AS dt_due,
    paid_date               AS dt_paid,
    created_at              AS ts_created,
    year,
    month,
    day

FROM

    datalake_rental_guarantee_platform_raw.agreement_payment_aud
