SELECT
        id,
        propose_id                  AS id_propose,
        previous_monthly_amount,
        updated_monthly_amount,
        due_date                    AS dt_due,
        created_at                  AS ts_created,
        updated_at                  AS ts_updated
FROM
    datalake_rental_guarantee_platform_raw.renewal_inconsistencies_corrected
