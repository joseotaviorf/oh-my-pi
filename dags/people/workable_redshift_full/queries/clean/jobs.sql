SELECT
    -- ids
    id,
    -- non-ids
    department_id AS id_department,
    pipeline_id AS id_pipeline,
    location_id AS id_location,
    -- non-metrics
    title,
    department,
    code,
    state,
    shortcode,
    country_code,
    state_code,
    city,
    zip_code,
    advertise_country_code,
    advertise_state_code,
    advertise_city,
    advertise_zip_code,
    employment_type,
    `function`,
    industry,
    experience,
    education,
    salary_currency,
    subregion,
    coords,
    access_level,
    -- metrics
    salary_from,
    salary_to,
    advertise_cost,
    candidates_count,
    free_postings_count,
    paid_postings_count,
    owned_postings_count,
    -- booleans
    telecommuting AS is_telecommuting,
    advertise_elsewhere AS has_advertise_elsewhere,
    -- timestamps
    job_created_at AS ts_job_created,
    first_published_at AS ts_first_publis,
    last_published_at AS ts_last_publish,
    first_screening_at AS ts_first_screening,
    first_interview_at AS ts_first_interview,
    first_offer_at AS ts_first_offer,
    first_hire_at AS ts_first_hire,
    updated_at AS ts_updated,
    NOW() AS ts_load
FROM 
    datalake_workable_redshift_raw.jobs
WHERE 
    MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
QUALIFY 
    updated_at = MAX(updated_at) OVER (PARTITION BY id)