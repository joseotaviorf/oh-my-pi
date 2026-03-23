SELECT
    -- ids
    id AS id_offer,
    application_id AS id_application,
    job_id AS id_job,
    candidate_id AS id_candidate,
    opening_id AS id_opening,
    -- text fields
    status,
    custom_fields.workplace_address.value AS workplace_address,
    custom_fields.employment_type.value AS employment_type,
    custom_fields.workplace.value AS workplace,
    custom_fields.reporting_to_manager.value.name AS reporting_to_manager_name,
    -- numeric
    version,
    custom_fields.salary.value.unit AS salary_unit,
    custom_fields.brasil_annual_salary_amount.value.unit AS annual_salary_unit,
    custom_fields.sign_on_bonus.value.unit AS hiring_bonus_unit,
    custom_fields.stock_options_cash_amount_offered.value.unit AS stock_options_cash_unit,
    CAST(custom_fields.salary.value.value AS DECIMAL(10,2)) AS salary_value,
    CAST(custom_fields.brasil_annual_salary_amount.value.value AS DECIMAL(10,2)) AS annual_salary_value,
    CAST(custom_fields.sign_on_bonus.value.value AS DECIMAL(10,2)) AS hiring_bonus_value,
    CAST(custom_fields.stock_options_cash_amount_offered.value.value AS DECIMAL(10,2)) AS stock_options_cash_value,
    -- boolean
    CAST(custom_fields.include_hiring_bonus.value AS BOOLEAN) AS has_hiring_bonus,
    -- dates & timestamps
    CAST(custom_fields.offer_expiration_date.value AS DATE) AS dt_offer_expires,
    CAST(custom_fields.trial_period.value AS DATE) AS dt_trial_period_ends,
    CAST(created_at AS TIMESTAMP) AS ts_created,
    CAST(updated_at AS TIMESTAMP) AS ts_updated,
    CAST(sent_on AS TIMESTAMP) AS ts_sent,
    CAST(resolved_at AS TIMESTAMP) AS ts_resolved,
    CAST(starts_on AS TIMESTAMP) AS ts_started,
    NOW() AS ts_load,
    -- partitions
    year,
    month,
    day
FROM
    datalake_greenhouse_v3_raw.offers
