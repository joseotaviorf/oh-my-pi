-- Candidate application funnel (Workable + Greenhouse v3) by candidate, job and stage, for the TA daily dashboard.
-- Exception: there is no DW path for recruiting funnel data. The Workable leg is inlined from the frozen
-- datalake_workable_redshift_clean tables (replacing datalake_people_analytics_sandbox.ta_funnel_accumulated)
-- and job opening close dates come from datalake_hiring.job_openings (DBP-1902).
WITH workable_last_update AS (
    SELECT
        MAX(FROM_UTC_TIMESTAMP(activities.ts_activity_created, 'America/Sao_Paulo')) AS last_activity_datetime
    FROM
        datalake_workable_redshift_clean.activities AS activities
),
workable_activities AS (
    SELECT
        activities.id AS id_activity,
        activities.id_candidate,
        activities.candidate_name,
        activities.id_member,
        activities.id_target_stage,
        activities.id_stage,
        activities.id_job,
        activities.action,
        CASE
            WHEN activities.id IN (1394616084, 1394588800, 1394863946) THEN CAST('2024-11-29' AS TIMESTAMP)
            WHEN activities.id IN (1264164329, 1264180153, 1266865367, 1266841737, 1272954638) THEN CAST('2024-09-01' AS TIMESTAMP)
            WHEN activities.id = 1364898106 THEN CAST('2024-10-28' AS TIMESTAMP)
            WHEN activities.id = 1362685102 THEN CAST('2024-10-29' AS TIMESTAMP)
            WHEN activities.id = 1364911638 THEN CAST('2024-11-01' AS TIMESTAMP)
            ELSE activities.ts_activity_created
        END AS ts_activity_created
    FROM
        datalake_workable_redshift_clean.activities AS activities
),
workable_hired_datetimes AS (
    SELECT
        activities.id_candidate,
        MIN(FROM_UTC_TIMESTAMP(activities.ts_activity_created, 'America/Sao_Paulo')) AS first_hired_datetime,
        MAX(FROM_UTC_TIMESTAMP(activities.ts_activity_created, 'America/Sao_Paulo')) AS last_hired_datetime
    FROM
        workable_activities AS activities
    WHERE
        LOWER(activities.action) LIKE '%hired%'
    GROUP BY
        activities.id_candidate
),
workable_disqualified_datetimes AS (
    SELECT
        activities.id_candidate,
        MIN(FROM_UTC_TIMESTAMP(activities.ts_activity_created, 'America/Sao_Paulo')) AS first_disqualified_datetime,
        MAX(FROM_UTC_TIMESTAMP(activities.ts_activity_created, 'America/Sao_Paulo')) AS last_disqualified_datetime
    FROM
        workable_activities AS activities
    WHERE
        LOWER(activities.action) LIKE '%disqualified%'
    GROUP BY
        activities.id_candidate
),
workable_reverted_datetimes AS (
    SELECT
        activities.id_candidate,
        MAX(FROM_UTC_TIMESTAMP(activities.ts_activity_created, 'America/Sao_Paulo')) AS last_reverted_datetime
    FROM
        workable_activities AS activities
    WHERE
        LOWER(activities.action) LIKE '%revert%'
    GROUP BY
        activities.id_candidate
),
workable_activity_datetimes AS (
    SELECT
        activities.id_candidate,
        MIN(FROM_UTC_TIMESTAMP(activities.ts_activity_created, 'America/Sao_Paulo')) AS first_activity_datetime,
        MAX(FROM_UTC_TIMESTAMP(activities.ts_activity_created, 'America/Sao_Paulo')) AS last_activity_datetime
    FROM
        workable_activities AS activities
    WHERE
        activities.action NOT LIKE '%employee-created%'
    GROUP BY
        activities.id_candidate
),
workable_candidate_status_base AS (
    SELECT DISTINCT
        activities.id_candidate,
        CASE
            WHEN (hired.last_hired_datetime IS NOT NULL AND disqualified.last_disqualified_datetime IS NULL)
                OR (hired.last_hired_datetime > disqualified.last_disqualified_datetime) THEN 'hired'
            WHEN disqualified.last_disqualified_datetime IS NOT NULL
                AND (
                    reverted.last_reverted_datetime IS NULL
                    OR disqualified.last_disqualified_datetime > reverted.last_reverted_datetime
                )
                AND (
                    hired.last_hired_datetime IS NULL
                    OR disqualified.last_disqualified_datetime >= hired.last_hired_datetime
                ) THEN 'disqualified'
            WHEN candidates.is_snoozed IS TRUE THEN 'snoozed'
            ELSE 'active'
        END AS status,
        hired.first_hired_datetime,
        disqualified.last_disqualified_datetime,
        activity.first_activity_datetime,
        activity.last_activity_datetime
    FROM
        workable_activities AS activities
    LEFT JOIN
        datalake_workable_redshift_clean.candidates AS candidates
            ON candidates.id = activities.id_candidate
    LEFT JOIN
        workable_hired_datetimes AS hired
            ON hired.id_candidate = activities.id_candidate
    LEFT JOIN
        workable_disqualified_datetimes AS disqualified
            ON disqualified.id_candidate = activities.id_candidate
    LEFT JOIN
        workable_activity_datetimes AS activity
            ON activity.id_candidate = activities.id_candidate
    LEFT JOIN
        workable_reverted_datetimes AS reverted
            ON reverted.id_candidate = activities.id_candidate
    WHERE
        activities.id_candidate IS NOT NULL
),
workable_candidate_status_ranked AS (
    SELECT
        status_base.id_candidate,
        status_base.status,
        CASE
            WHEN status_base.status = 'hired' THEN status_base.first_hired_datetime
            WHEN status_base.status = 'disqualified' THEN status_base.last_disqualified_datetime
        END AS resolved_datetime,
        status_base.first_activity_datetime,
        status_base.last_activity_datetime,
        ROW_NUMBER() OVER (
            PARTITION BY status_base.id_candidate
            ORDER BY status_base.last_activity_datetime DESC
        ) AS status_rank
    FROM
        workable_candidate_status_base AS status_base
),
workable_candidate_status AS (
    SELECT
        status_ranked.id_candidate,
        status_ranked.status,
        status_ranked.resolved_datetime,
        COALESCE(status_ranked.resolved_datetime, status_ranked.last_activity_datetime) AS reference_datetime,
        status_ranked.first_activity_datetime,
        status_ranked.last_activity_datetime
    FROM
        workable_candidate_status_ranked AS status_ranked
    WHERE
        status_ranked.status_rank = 1
),
workable_job_starts AS (
    SELECT
        activities.id_candidate,
        activities.id_job,
        activities.ts_activity_created AS ts_job_start
    FROM
        workable_activities AS activities
    WHERE
        LOWER(activities.action) IN ('candidate applied', 'candidate uploaded', 'candidate moved to another job', 'candidate copied')
        AND LOWER(activities.candidate_name) NOT LIKE '%teste%'
),
-- Replaces the legacy Python loop that COALESCEd one id_job column per candidate job change:
-- for each activity, keep the job of the most recent job-start event at or before the activity.
workable_activity_jobs_ranked AS (
    SELECT
        activities.id_activity,
        job_starts.id_job,
        ROW_NUMBER() OVER (
            PARTITION BY activities.id_activity
            ORDER BY job_starts.ts_job_start DESC
        ) AS job_start_rank
    FROM
        workable_activities AS activities
    LEFT JOIN
        workable_job_starts AS job_starts
            ON job_starts.id_candidate = activities.id_candidate
            AND activities.ts_activity_created >= job_starts.ts_job_start
),
workable_activity_jobs AS (
    SELECT
        activity_jobs.id_activity,
        activity_jobs.id_job AS job_id
    FROM
        workable_activity_jobs_ranked AS activity_jobs
    WHERE
        activity_jobs.job_start_rank = 1
),
workable_stage_datetimes AS (
    SELECT
        activities.id_candidate,
        activity_jobs.job_id AS id_job,
        COALESCE(activities.id_target_stage, activities.id_stage) AS id_stage,
        MIN(FROM_UTC_TIMESTAMP(activities.ts_activity_created, 'America/Sao_Paulo')) AS stage_first_datetime,
        MAX(FROM_UTC_TIMESTAMP(activities.ts_activity_created, 'America/Sao_Paulo')) AS stage_last_datetime
    FROM
        workable_activities AS activities
    LEFT JOIN
        workable_activity_jobs AS activity_jobs
            ON activity_jobs.id_activity = activities.id_activity
    WHERE
        activities.id_candidate IS NOT NULL
        AND activity_jobs.job_id IS NOT NULL
        -- keeps only actions performed by the TA team or hiring managers
        AND activities.id_member IS NOT NULL
    GROUP BY
        activities.id_candidate,
        activity_jobs.job_id,
        COALESCE(activities.id_target_stage, activities.id_stage)
),
workable_stage_status AS (
    SELECT
        stage_datetimes.id_candidate,
        stage_datetimes.id_job,
        stage_datetimes.id_stage,
        CASE
            WHEN candidate_status.reference_datetime > stage_datetimes.stage_last_datetime THEN 'approved'
            WHEN candidate_status.status = 'hired'
                AND LOWER(REPLACE(stages.name, '*', '')) <> 'hired' THEN 'approved'
            ELSE candidate_status.status
        END AS stage_status,
        stage_datetimes.stage_first_datetime,
        stage_datetimes.stage_last_datetime,
        candidate_status.status AS candidate_status,
        candidate_status.resolved_datetime AS candidate_resolved_datetime,
        candidate_status.reference_datetime AS candidate_reference_datetime
    FROM
        workable_stage_datetimes AS stage_datetimes
    LEFT JOIN
        workable_candidate_status AS candidate_status
            ON candidate_status.id_candidate = stage_datetimes.id_candidate
    LEFT JOIN
        datalake_workable_redshift_clean.stages AS stages
            ON stages.id = stage_datetimes.id_stage
),
-- Excludes candidate ids that must not compose the funnel.
workable_valid_candidates AS (
    SELECT DISTINCT
        activities.id_candidate
    FROM
        workable_activities AS activities
    WHERE
        (
            -- drops stray records that were not moved along with the candidate
            LOWER(activities.action) IN ('candidate applied', 'candidate uploaded', 'candidate moved to another job', 'candidate copied')
            -- valid candidates without an initial action
            OR activities.id_candidate IN (471417068, 480004740)
        )
        -- drops the TA dummy candidate
        AND LOWER(activities.candidate_name) NOT LIKE '%teste%'
),
workable_stages AS (
    SELECT
        stages.id,
        CASE
            -- same stage; the candidate record identifies the source
            WHEN stages.name IN ('Sourced', 'Applied') THEN 'Applied/Sourced'
            ELSE REPLACE(stages.name, '*', '')
        END AS name,
        stages.position
    FROM
        datalake_workable_redshift_clean.stages AS stages
),
workable_jobs AS (
    SELECT DISTINCT
        jobs.id,
        jobs.state,
        CASE
            -- overrides the department of archived jobs
            WHEN jobs.id IN (4234429) THEN 'Data'
            ELSE jobs.department
        END AS department,
        CASE
            -- points archived tech jobs at the current pipeline
            WHEN jobs.id IN (4136045, 4220186, 4100867) THEN 715387
            ELSE jobs.id_pipeline
        END AS id_pipeline
    FROM
        datalake_workable_redshift_clean.jobs AS jobs
),
-- Stage where the candidate was disqualified.
workable_disqualified_stages AS (
    SELECT DISTINCT
        activities.id_candidate,
        activities.id_job,
        stages.position
    FROM
        workable_activities AS activities
    LEFT JOIN
        workable_stages AS stages
            ON stages.id = COALESCE(activities.id_target_stage, activities.id_stage)
    INNER JOIN
        workable_stage_status AS stage_status
            ON stage_status.id_candidate = activities.id_candidate
            AND stage_status.id_job = activities.id_job
            AND stage_status.id_stage = COALESCE(activities.id_target_stage, activities.id_stage)
    WHERE
        stage_status.stage_status = 'disqualified'
),
-- Stages that happen after the disqualification stage.
workable_future_stages_to_drop AS (
    SELECT
        activities.id_candidate,
        activities.id_job,
        stages.position
    FROM
        workable_activities AS activities
    LEFT JOIN
        workable_stages AS stages
            ON stages.id = COALESCE(activities.id_target_stage, activities.id_stage)
    INNER JOIN
        workable_disqualified_stages AS disqualified_stages
            ON disqualified_stages.id_candidate = activities.id_candidate
            AND disqualified_stages.id_job = activities.id_job
            AND stages.position > disqualified_stages.position
),
-- Joins back to raw activities on the raw id_job and unpatched timestamp on purpose:
-- the legacy ta_funnel_accumulated behaved the same way, and switching to the resolved
-- job / patched timestamp identity would add ~13.7k candidate x stage rows (+3.7%)
-- that the legacy export never had (measured on EMR, DBP-1902).
workable_funnel_accumulated AS (
    SELECT DISTINCT
        activities.id_candidate AS candidate_id,
        candidates.name AS candidate_name,
        CASE
            WHEN stage_status.candidate_status = 'active'
                AND LOWER(jobs.state) NOT IN ('published', 'open for internal use') THEN 'archived'
            ELSE stage_status.candidate_status
        END AS candidate_status,
        stage_status.candidate_resolved_datetime,
        stage_status.candidate_reference_datetime AS candidate_last_activity_datetime,
        COALESCE(activities.id_target_stage, activities.id_stage) AS stage_id,
        stages.name AS stage,
        CAST(stages.position AS INT) AS stage_position,
        stage_status.stage_status,
        stage_status.stage_last_datetime AS stage_last_activity_datetime,
        candidates.source_category AS candidate_source,
        candidates.ts_candidate_created AS candidate_created_datetime,
        activity_jobs.job_id,
        activities.job_title,
        jobs.state AS job_state,
        jobs.department AS job_department,
        pipelines.name AS job_pipeline,
        last_update.last_activity_datetime AS last_updated_datetime
    FROM
        datalake_workable_redshift_clean.activities AS activities
    CROSS JOIN
        workable_last_update AS last_update
    INNER JOIN
        workable_stage_status AS stage_status
            ON stage_status.id_candidate = activities.id_candidate
            AND stage_status.id_job = activities.id_job
            AND stage_status.id_stage = COALESCE(activities.id_target_stage, activities.id_stage)
            AND FROM_UTC_TIMESTAMP(activities.ts_activity_created, 'America/Sao_Paulo') = stage_status.stage_last_datetime
    INNER JOIN
        workable_valid_candidates AS valid_candidates
            ON valid_candidates.id_candidate = activities.id_candidate
    LEFT JOIN
        workable_stages AS stages
            ON stages.id = COALESCE(activities.id_target_stage, activities.id_stage)
    LEFT JOIN
        datalake_workable_redshift_clean.candidates AS candidates
            ON candidates.id = activities.id_candidate
    LEFT JOIN
        workable_activity_jobs AS activity_jobs
            ON activity_jobs.id_activity = activities.id
    LEFT JOIN
        workable_jobs AS jobs
            ON jobs.id = COALESCE(activity_jobs.job_id, activities.id_job)
    LEFT JOIN
        datalake_workable_redshift_clean.pipelines AS pipelines
            ON pipelines.id = jobs.id_pipeline
    LEFT JOIN
        workable_future_stages_to_drop AS future_stages
            ON future_stages.id_candidate = activities.id_candidate
            AND future_stages.id_job = activities.id_job
            AND future_stages.position = stages.position
    WHERE
        (candidates.name IS NOT NULL OR stage_status.candidate_resolved_datetime IS NOT NULL)
        -- drops stages after the disqualification
        AND future_stages.id_candidate IS NULL
        AND activities.id_job NOT IN (2641112)
),
workable_funnel AS (
    SELECT
        accumulated.candidate_id,
        accumulated.job_id,
        accumulated.candidate_name,
        accumulated.candidate_status,
        accumulated.stage AS candidate_stage,
        accumulated.candidate_source,
        accumulated.job_title,
        accumulated.job_department,
        parent_department.name AS job_department_macro,
        accumulated.job_pipeline,
        accumulated.job_state,
        accumulated.stage_status AS candidate_stage_status,
        accumulated.stage_position AS candidate_stage_position,
        DATE_TRUNC('MONTH', accumulated.candidate_last_activity_datetime) AS candidate_last_activity,
        accumulated.candidate_resolved_datetime,
        accumulated.candidate_last_activity_datetime,
        accumulated.candidate_created_datetime,
        accumulated.last_updated_datetime,
        'wb' AS sistema
    FROM
        workable_funnel_accumulated AS accumulated
    LEFT JOIN
        datalake_workable_redshift_clean.jobs AS jobs
            ON jobs.id = accumulated.job_id
    LEFT JOIN
        datalake_workable_redshift_clean.departments AS department
            ON department.id = jobs.id_department
    LEFT JOIN
        datalake_workable_redshift_clean.departments AS parent_department
            ON parent_department.id = department.id_parent
    WHERE
        (
            accumulated.candidate_resolved_datetime IS NULL
            OR accumulated.candidate_last_activity_datetime >= ADD_MONTHS(accumulated.last_updated_datetime, -18)
        )
        AND accumulated.stage_status NOT IN ('archived', 'active')
        AND accumulated.candidate_status <> 'active'
),
greenhouse_last_update AS (
    SELECT
        MAX(application_stages.ts_updated) AS last_updated_datetime
    FROM
        datalake_greenhouse_v3_clean.application_stages AS application_stages
),
greenhouse_stage_helper AS (
    SELECT
        application_stages.id_application,
        job_interview_stages.id_job,
        MAX(CASE WHEN application_stages.ts_entered IS NOT NULL THEN job_interview_stages.sort_order ELSE -1 END) AS max_stage_entered_per_job,
        MAX(CASE WHEN application_stages.is_current THEN job_interview_stages.sort_order ELSE -1 END) AS current_stage_order
    FROM
        datalake_greenhouse_v3_clean.application_stages AS application_stages
    LEFT JOIN
        datalake_greenhouse_v3_clean.job_interview_stages AS job_interview_stages
            ON job_interview_stages.id_job_interview_stage = application_stages.id_job_interview_stage
    GROUP BY
        application_stages.id_application,
        job_interview_stages.id_job
),
greenhouse_funnel AS (
    SELECT
        applications.id_application AS candidate_id,
        jobs.id_requisition AS job_id,
        CONCAT(candidates.first_name, ' ', candidates.last_name) AS candidate_name,
        applications.status AS candidate_status,
        job_interview_stages.name AS candidate_stage,
        sources.name AS candidate_source,
        jobs.name AS job_title,
        department.name AS job_department,
        parent_department.name AS job_department_macro,
        REPLACE(template.name, '[TEMPLATE] ', '') AS job_pipeline,
        jobs.status AS job_state,
        CASE
            WHEN applications.status = 'hired' THEN 'approved'
            WHEN job_interview_stages.sort_order < stage_helper.current_stage_order THEN 'approved'
            WHEN applications.status <> 'rejected'
                AND job_interview_stages.sort_order = stage_helper.current_stage_order THEN 'active'
            WHEN applications.status = 'rejected'
                AND job_interview_stages.sort_order = stage_helper.current_stage_order THEN 'disqualified'
            WHEN applications.status <> 'hired'
                AND job_interview_stages.sort_order > stage_helper.current_stage_order THEN 'not-started'
        END AS candidate_stage_status,
        job_interview_stages.sort_order AS candidate_stage_position,
        DATE(FROM_UTC_TIMESTAMP(
            CASE
                WHEN job_interview_stages.name = 'Application Review'
                    THEN application_stages.ts_entered
                WHEN applications.status = 'rejected'
                    AND job_interview_stages.sort_order = stage_helper.current_stage_order
                    AND job_interview_stages.id_job = applications.id_job
                    THEN applications.ts_rejected
                WHEN (
                        (job_interview_stages.id_job = applications.id_job AND stage_helper.current_stage_order > job_interview_stages.sort_order)
                        OR (job_interview_stages.id_job <> applications.id_job AND stage_helper.max_stage_entered_per_job > job_interview_stages.sort_order)
                        OR applications.status = 'hired'
                    )
                    AND application_stages.ts_exited IS NULL
                    THEN MAX(
                            COALESCE(application_stages.ts_exited, application_stages.ts_entered)
                        ) OVER (
                            PARTITION BY applications.id_application, job_interview_stages.id_job
                            ORDER BY job_interview_stages.sort_order
                            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
                        )
                ELSE COALESCE(application_stages.ts_exited, applications.ts_last_activity)
            END,
            'America/Sao_Paulo'
        )) AS candidate_last_activity,
        CASE
            WHEN applications.status = 'rejected'
                AND job_interview_stages.id_job = applications.id_job THEN applications.ts_rejected
            WHEN applications.status = 'hired'
                AND job_interview_stages.id_job = applications.id_job THEN job_openings.ts_closed
        END AS candidate_resolved_datetime,
        applications.ts_last_activity AS candidate_last_activity_datetime,
        applications.ts_created AS candidate_created_datetime,
        last_update.last_updated_datetime,
        'gh' AS sistema
    FROM
        datalake_greenhouse_v3_clean.application_stages AS application_stages
    CROSS JOIN
        greenhouse_last_update AS last_update
    LEFT JOIN
        datalake_greenhouse_v3_clean.job_interview_stages AS job_interview_stages
            ON job_interview_stages.id_job_interview_stage = application_stages.id_job_interview_stage
    LEFT JOIN
        datalake_greenhouse_v3_clean.applications AS applications
            ON applications.id_application = application_stages.id_application
    LEFT JOIN
        datalake_greenhouse_v3_clean.sources AS sources
            ON sources.id_source = applications.id_source
    LEFT JOIN
        datalake_greenhouse_v3_clean.candidates AS candidates
            ON candidates.id_candidate = applications.id_candidate
    LEFT JOIN
        greenhouse_stage_helper AS stage_helper
            ON stage_helper.id_application = application_stages.id_application
            AND stage_helper.id_job = job_interview_stages.id_job
    LEFT JOIN
        datalake_greenhouse_v3_clean.jobs AS jobs
            ON jobs.id_job = job_interview_stages.id_job
    LEFT JOIN
        datalake_hiring.job_openings AS job_openings
            ON job_openings.id_application_hired = applications.id_application
            AND LOWER(job_openings.close_reason) LIKE 'hire%'
    LEFT JOIN
        datalake_greenhouse_v3_clean.departments AS department
            ON department.id_department = jobs.id_department
    LEFT JOIN
        datalake_greenhouse_v3_clean.departments AS parent_department
            ON parent_department.id_department = department.id_parent
    LEFT JOIN
        datalake_greenhouse_v3_clean.jobs AS template
            ON template.id_job = jobs.id_copied_from
            AND template.is_template = TRUE
    WHERE
        job_interview_stages.id_job = applications.id_job
        AND NOT applications.is_prospect
        AND jobs.status <> 'draft'
        AND job_interview_stages.is_active
        -- drops stages without real history
        AND application_stages.ts_entered IS NOT NULL
        AND applications.ts_last_activity >= ADD_MONTHS(last_update.last_updated_datetime, -18)
        AND LOWER(jobs.name) NOT LIKE '%test%'
        AND LOWER(jobs.name) NOT LIKE '%template%'
        AND jobs.name <> 'Sample Job 1'
        AND jobs.ts_created >= '2025-09-11'
        AND jobs.employment_type NOT IN ('Contract', 'Temporary')
        AND jobs.id_requisition NOT IN ('651', '643')
        AND (
            (
                ARRAY_CONTAINS(candidates.tags, 'Workable Migration')
                AND (jobs.ts_closed > '2025-09-01' OR jobs.ts_closed IS NULL)
            )
            OR NOT ARRAY_CONTAINS(candidates.tags, 'Workable Migration')
            OR candidates.tags IS NULL
        )
),
prospect_applications AS (
    SELECT
        applications.id_application,
        applications.id_candidate,
        applications.ts_created AS applied_at,
        prospective_job_id AS id_job
    FROM
        datalake_greenhouse_v3_clean.applications AS applications
    LATERAL VIEW EXPLODE(applications.prospective_job_ids) exploded_jobs AS prospective_job_id
    WHERE
        applications.is_prospect = TRUE
        AND applications.prospective_job_ids IS NOT NULL
),
prospect_applications_ranked AS (
    SELECT
        prospect_applications.id_application,
        prospect_applications.id_candidate,
        prospect_applications.applied_at,
        prospect_applications.id_job,
        ROW_NUMBER() OVER (
            PARTITION BY prospect_applications.id_candidate, prospect_applications.id_job
            ORDER BY prospect_applications.applied_at ASC
        ) AS application_rank
    FROM
        prospect_applications
),
prospects AS (
    SELECT DISTINCT
        prospect_applications.id_application,
        prospect_applications.id_candidate,
        prospect_applications.applied_at,
        jobs.id_requisition AS job_id,
        prospect_applications.id_job
    FROM
        prospect_applications_ranked AS prospect_applications
    LEFT JOIN
        datalake_greenhouse_v3_clean.jobs AS jobs
            ON jobs.id_job = prospect_applications.id_job
    WHERE
        prospect_applications.application_rank = 1
),
prospect_funnel AS (
    SELECT DISTINCT
        prospects.id_application AS candidate_id,
        prospects.job_id,
        candidates.full_name AS candidate_name,
        CASE
            WHEN applications.status = 'in_process' THEN 'prospect'
            ELSE applications.status
        END AS candidate_status,
        'Applied/Sourced - Prospect' AS candidate_stage,
        sources.name AS candidate_source,
        jobs.name AS job_title,
        department.name AS job_department,
        parent_department.name AS job_department_macro,
        REPLACE(template.name, '[TEMPLATE] ', '') AS job_pipeline,
        jobs.status AS job_state,
        CASE
            WHEN applications.status = 'converted' THEN 'approved'
            WHEN applications.status = 'rejected' THEN 'disqualified'
            WHEN applications.status = 'in_process' THEN 'prospect'
            ELSE applications.status
        END AS candidate_stage_status,
        1 AS candidate_stage_position,
        CASE
            WHEN applications.status = 'rejected' THEN applications.ts_rejected
            WHEN applications.status = 'hired' THEN job_openings.ts_closed
            ELSE DATE_TRUNC('MONTH', applications.ts_last_activity)
        END AS candidate_last_activity,
        CASE
            WHEN applications.status = 'rejected' THEN applications.ts_rejected
            WHEN applications.status = 'hired' THEN job_openings.ts_closed
        END AS candidate_resolved_datetime,
        applications.ts_last_activity AS candidate_last_activity_datetime,
        applications.ts_created AS candidate_created_datetime,
        last_update.last_updated_datetime,
        'gh' AS sistema
    FROM
        prospects
    CROSS JOIN
        greenhouse_last_update AS last_update
    LEFT JOIN
        datalake_greenhouse_v3_clean.candidates AS candidates
            ON candidates.id_candidate = prospects.id_candidate
    LEFT JOIN
        datalake_greenhouse_v3_clean.applications AS applications
            ON applications.id_application = prospects.id_application
    LEFT JOIN
        datalake_greenhouse_v3_clean.sources AS sources
            ON sources.id_source = applications.id_source
    LEFT JOIN
        datalake_greenhouse_v3_clean.jobs AS jobs
            ON jobs.id_job = prospects.id_job
    LEFT JOIN
        datalake_greenhouse_v3_clean.departments AS department
            ON department.id_department = jobs.id_department
    LEFT JOIN
        datalake_greenhouse_v3_clean.departments AS parent_department
            ON parent_department.id_department = department.id_parent
    LEFT JOIN
        datalake_greenhouse_v3_clean.jobs AS template
            ON template.id_job = jobs.id_copied_from
            AND template.is_template = TRUE
    LEFT JOIN
        datalake_hiring.job_openings AS job_openings
            ON job_openings.id_application_hired = applications.id_application
            AND LOWER(job_openings.close_reason) LIKE 'hire%'
    WHERE
        (
            ARRAY_CONTAINS(candidates.tags, 'Workable Migration')
            AND (jobs.ts_closed > '2025-09-01' OR jobs.ts_closed IS NULL)
        )
        OR NOT ARRAY_CONTAINS(candidates.tags, 'Workable Migration')
        OR candidates.tags IS NULL
),
-- Greenhouse does not map Hired as a separate stage, so every hired candidate gets a manual "Hired" row.
hired_stage_funnel AS (
    SELECT DISTINCT
        funnel.candidate_id,
        funnel.job_id,
        funnel.candidate_name,
        funnel.candidate_status,
        'Hired' AS candidate_stage,
        funnel.candidate_source,
        funnel.job_title,
        funnel.job_department,
        funnel.job_department_macro,
        funnel.job_pipeline,
        funnel.job_state,
        'hired' AS candidate_stage_status,
        1000 AS candidate_stage_position,
        COALESCE(funnel.candidate_resolved_datetime, funnel.candidate_last_activity) AS candidate_last_activity,
        funnel.candidate_resolved_datetime,
        funnel.candidate_last_activity_datetime,
        funnel.candidate_created_datetime,
        funnel.last_updated_datetime,
        funnel.sistema
    FROM
        greenhouse_funnel AS funnel
    WHERE
        funnel.candidate_status = 'hired'
),
applications_funnel AS (
    SELECT
        candidate_id,
        job_id,
        candidate_name,
        candidate_status,
        candidate_stage,
        candidate_source,
        job_title,
        job_department,
        job_department_macro,
        job_pipeline,
        job_state,
        candidate_stage_status,
        candidate_stage_position,
        candidate_last_activity,
        candidate_resolved_datetime,
        candidate_last_activity_datetime,
        candidate_created_datetime,
        last_updated_datetime,
        sistema
    FROM
        workable_funnel
    UNION ALL
    SELECT
        candidate_id,
        job_id,
        candidate_name,
        candidate_status,
        candidate_stage,
        candidate_source,
        job_title,
        job_department,
        job_department_macro,
        job_pipeline,
        job_state,
        candidate_stage_status,
        candidate_stage_position,
        candidate_last_activity,
        candidate_resolved_datetime,
        candidate_last_activity_datetime,
        candidate_created_datetime,
        last_updated_datetime,
        sistema
    FROM
        greenhouse_funnel
    UNION ALL
    SELECT
        candidate_id,
        job_id,
        candidate_name,
        candidate_status,
        candidate_stage,
        candidate_source,
        job_title,
        job_department,
        job_department_macro,
        job_pipeline,
        job_state,
        candidate_stage_status,
        candidate_stage_position,
        candidate_last_activity,
        candidate_resolved_datetime,
        candidate_last_activity_datetime,
        candidate_created_datetime,
        last_updated_datetime,
        sistema
    FROM
        prospect_funnel
    UNION ALL
    SELECT
        candidate_id,
        job_id,
        candidate_name,
        candidate_status,
        candidate_stage,
        candidate_source,
        job_title,
        job_department,
        job_department_macro,
        job_pipeline,
        job_state,
        candidate_stage_status,
        candidate_stage_position,
        candidate_last_activity,
        candidate_resolved_datetime,
        candidate_last_activity_datetime,
        candidate_created_datetime,
        last_updated_datetime,
        sistema
    FROM
        hired_stage_funnel
),
classified_funnel AS (
    SELECT
        funnel.candidate_id,
        funnel.candidate_name,
        funnel.candidate_status,
        DATE(funnel.candidate_last_activity) AS last_activity,
        funnel.candidate_stage,
        funnel.candidate_stage_position,
        funnel.candidate_stage_status,
        funnel.candidate_source,
        funnel.job_id,
        funnel.job_title,
        funnel.job_state,
        funnel.job_department,
        funnel.job_department_macro,
        funnel.job_pipeline,
        DATE(funnel.last_updated_datetime) AS last_updated_datetime,
        funnel.sistema,
        CASE
            WHEN funnel.job_pipeline IN (
                'Product & Design',
                'Engineering & Data',
                'Design  B10+',
                'Design - B9 and Below',
                'Product B10+ (Product , PGM, PMM)',
                'Product B9- (Product, PGM, PMM)',
                'Tech IC B10+ (Eng, Data, Tech Platform)',
                'Tech IC B9-  (Eng Data, Tech Platform)',
                'Tech Managers (Eng, Data, Tech Platform)',
                'Tech TLM  (Eng, Data, Tech Platform)'
            ) THEN 'P&T'
            WHEN funnel.job_department = 'Banco de Talentos' THEN 'Banco de Talentos'
            ELSE 'Others'
        END AS grupo_pipe
    FROM
        applications_funnel AS funnel
),
-- One aggregated row per resolved stage; candidate identity is masked because the grain is a count.
aggregated_stages AS (
    SELECT
        '-' AS candidate_id,
        '-' AS candidate_name,
        funnel.candidate_status,
        funnel.last_activity,
        funnel.candidate_stage,
        funnel.candidate_stage_position,
        funnel.candidate_stage_status,
        funnel.candidate_source,
        funnel.job_id,
        funnel.job_title,
        funnel.job_state,
        funnel.job_department,
        funnel.job_department_macro,
        funnel.job_pipeline,
        funnel.last_updated_datetime,
        funnel.sistema,
        funnel.grupo_pipe,
        COUNT(1) AS candidate_count
    FROM
        classified_funnel AS funnel
    WHERE
        funnel.candidate_stage_status NOT IN ('active', 'not-started')
    GROUP BY
        funnel.candidate_status,
        funnel.last_activity,
        funnel.candidate_stage,
        funnel.candidate_stage_position,
        funnel.candidate_stage_status,
        funnel.candidate_source,
        funnel.job_id,
        funnel.job_title,
        funnel.job_state,
        funnel.job_department,
        funnel.job_department_macro,
        funnel.job_pipeline,
        funnel.last_updated_datetime,
        funnel.sistema,
        funnel.grupo_pipe
),
-- One row per candidate still in process, so TA can act on the named pipeline.
active_applications AS (
    SELECT
        CAST(funnel.candidate_id AS STRING) AS candidate_id,
        funnel.candidate_name,
        funnel.candidate_status,
        funnel.last_activity,
        funnel.candidate_stage,
        funnel.candidate_stage_position,
        funnel.candidate_stage_status,
        funnel.candidate_source,
        funnel.job_id,
        funnel.job_title,
        funnel.job_state,
        funnel.job_department,
        funnel.job_department_macro,
        funnel.job_pipeline,
        funnel.last_updated_datetime,
        funnel.sistema,
        funnel.grupo_pipe,
        1 AS candidate_count
    FROM
        classified_funnel AS funnel
    WHERE
        funnel.candidate_status IN ('active', 'in_process')
        AND funnel.candidate_stage_status IN ('active')
),
funnel_export AS (
    SELECT
        candidate_id,
        candidate_name,
        candidate_status,
        last_activity,
        candidate_stage,
        candidate_stage_position,
        candidate_stage_status,
        candidate_source,
        job_id,
        job_title,
        job_state,
        job_department,
        job_department_macro,
        job_pipeline,
        last_updated_datetime,
        sistema,
        grupo_pipe,
        candidate_count
    FROM
        aggregated_stages
    UNION ALL
    SELECT
        candidate_id,
        candidate_name,
        candidate_status,
        last_activity,
        candidate_stage,
        candidate_stage_position,
        candidate_stage_status,
        candidate_source,
        job_id,
        job_title,
        job_state,
        job_department,
        job_department_macro,
        job_pipeline,
        last_updated_datetime,
        sistema,
        grupo_pipe,
        candidate_count
    FROM
        active_applications
)
SELECT
    funnel.candidate_id,
    funnel.candidate_name,
    funnel.candidate_status,
    funnel.last_activity,
    funnel.candidate_stage,
    funnel.candidate_stage_position,
    funnel.candidate_stage_status,
    funnel.candidate_source,
    funnel.job_id,
    funnel.job_title,
    funnel.job_state,
    funnel.job_department,
    funnel.job_department_macro,
    funnel.job_pipeline,
    funnel.last_updated_datetime,
    funnel.sistema,
    funnel.grupo_pipe,
    funnel.candidate_count,
    YEAR(DATE('{load_start_date}')) AS year,
    MONTH(DATE('{load_start_date}')) AS month,
    DAY(DATE('{load_start_date}')) AS day
FROM
    funnel_export AS funnel
