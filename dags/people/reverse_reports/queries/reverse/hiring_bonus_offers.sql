-- Accepted Greenhouse offers with a hiring bonus, for TA/Finance bonus payout processing.
WITH job_details AS (
    SELECT
        jobs.id_job,
        jobs.name AS job_title,
        departments.name AS department,
        jobs.l1_full_name,
        CASE
            WHEN template.name LIKE '[TEMPLATE]%' THEN SUBSTRING(template.name, 12)
            ELSE template.name
        END AS pipeline
    FROM
        datalake_greenhouse_v3_clean.jobs AS jobs
    LEFT JOIN
        datalake_greenhouse_v3_clean.departments AS departments
            ON departments.id_department = jobs.id_department
    LEFT JOIN
        datalake_greenhouse_v3_clean.jobs AS template
            ON jobs.id_copied_from = template.id_job
            AND template.is_template = TRUE
),
accepted_offers_with_bonus AS (
    SELECT
        offers.id_candidate,
        candidates.full_name AS candidate_name,
        offers.hiring_bonus_unit,
        offers.hiring_bonus_value,
        job_openings.band AS salary_band,
        job_openings.code AS requisition_code,
        job_details.job_title,
        job_details.department,
        job_openings.cost_center,
        offers.ts_started,
        offers.salary_value AS offered_salary,
        job_openings.salary_table,
        job_openings.career_path,
        job_openings.hiring_manager_email,
        job_details.pipeline,
        job_details.l1_full_name
    FROM
        datalake_greenhouse_v3_clean.offers AS offers
    LEFT JOIN
        datalake_hiring.job_openings AS job_openings
            ON job_openings.id_opening = offers.id_opening
    LEFT JOIN
        job_details
            ON job_details.id_job = offers.id_job
    LEFT JOIN
        datalake_greenhouse_v3_clean.candidates AS candidates
            ON candidates.id_candidate = offers.id_candidate
    WHERE
        LOWER(offers.status) = 'accepted'
        AND offers.has_hiring_bonus = TRUE
)
SELECT
    accepted_offers.id_candidate AS candidate_id,
    accepted_offers.candidate_name AS name,
    1 AS hiring_bonus,
    accepted_offers.hiring_bonus_unit AS hiring_bonus_currency,
    accepted_offers.hiring_bonus_value AS hiring_bonus_amount,
    accepted_offers.salary_band,
    accepted_offers.requisition_code AS requisition_id,
    accepted_offers.job_title,
    accepted_offers.department,
    accepted_offers.cost_center AS centrocusto,
    accepted_offers.ts_started AS dt_start,
    accepted_offers.offered_salary,
    accepted_offers.salary_table,
    accepted_offers.career_path AS carreer_path,
    accepted_offers.hiring_manager_email AS hiring_manager,
    accepted_offers.pipeline,
    DATE('{load_start_date}') AS last_update,
    accepted_offers.l1_full_name AS l1,
    YEAR(DATE('{load_start_date}')) AS year,
    MONTH(DATE('{load_start_date}')) AS month,
    DAY(DATE('{load_start_date}')) AS day
FROM
    accepted_offers_with_bonus AS accepted_offers
