SELECT
    -- ids
    id,
    application_id AS id_application,
    job_id AS id_job,
    candidate_id AS id_candidate,
    opening.id AS id_opening,
    -- text fields
    status,
    keyed_custom_fields.performance_bonus_type.value AS performance_bonus_type,
    keyed_custom_fields.workplace_address.value AS workplace_address,
    keyed_custom_fields.employment_type.value AS employment_type,
    keyed_custom_fields.workplace.value AS workplace,
    keyed_custom_fields.reporting_to_manager.value.name AS reporting_to_manager_name,
    keyed_custom_fields.car_allowance.value AS car_allowance,
    keyed_custom_fields.plan_m_dico.value AS medical_plan,
    CAST(opening.status AS STRING) AS opening_status,
    -- numeric
    version,
    keyed_custom_fields.salary.value.unit AS salary_unit,
    keyed_custom_fields.brasil_annual_salary_amount.value.unit AS annual_salary_unit,
    keyed_custom_fields.sign_on_bonus.value.unit AS hiring_bonus_unit,
    keyed_custom_fields.stock_options_cash_amount_offered.value.unit AS stock_options_cash_unit,
    CAST(keyed_custom_fields.salary.value.value AS DECIMAL(10,2)) AS salary_value,
    CAST(keyed_custom_fields.brasil_annual_salary_amount.value.value AS DECIMAL(10,2)) AS annual_salary_value,
    CAST(keyed_custom_fields.sign_on_bonus.value.value AS DECIMAL(10,2)) AS hiring_bonus_value,
    CAST(keyed_custom_fields.stock_options_cash_amount_offered.value.value AS DECIMAL(10,2)) AS stock_options_cash_value,
    -- boolean
    CAST(keyed_custom_fields.include_hiring_bonus.value AS BOOLEAN) AS has_hiring_bonus,
    -- dates & timestamps
    CAST(keyed_custom_fields.offer_expiration_date.value AS DATE) AS dt_offer_expires,
    CAST(keyed_custom_fields.trial_period.value AS DATE) AS dt_trial_period_ends,
    CAST(created_at AS TIMESTAMP) AS ts_created,
    CAST(updated_at AS TIMESTAMP) AS ts_updated,
    CAST(sent_at AS TIMESTAMP) AS ts_sent,
    CAST(resolved_at AS TIMESTAMP) AS ts_resolved,
    CAST(starts_at AS TIMESTAMP) AS ts_started,
    CAST(opening.opened_at AS TIMESTAMP) AS ts_opening_opened,
    CAST(opening.closed_at AS TIMESTAMP) AS ts_opening_closed,
    NOW() AS ts_load,
    -- partitions
    year,
    month,
    day
FROM
    datalake_greenhouse_raw.offers
WHERE
    DATE(updated_at) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')