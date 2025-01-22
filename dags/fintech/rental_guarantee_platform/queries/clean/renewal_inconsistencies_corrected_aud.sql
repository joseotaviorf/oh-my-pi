SELECT
    id,
    propose_id          AS id_propose,
    propose_id_mod      AS id_propose_mod,
    previous_monthly_amount,
    previous_monthly_amount_mod,
    updated_monthly_amount,
    updated_monthly_amount_mod,
    rev,
    revtype             AS rev_type,
    revend              AS rev_end,
    due_date            AS dt_due,
    due_date_mod        AS dt_due_mod,
    created_at          AS ts_created,
    created_at_mod      AS ts_created_mod,
    updated_at          AS ts_updated,
    updated_at_mod      AS ts_updated_mod
FROM
    datalake_rental_guarantee_platform_raw.renewal_inconsistencies_corrected_aud
