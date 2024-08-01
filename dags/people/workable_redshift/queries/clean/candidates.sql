SELECT
    -- ids
    id,
    -- non-ids
    job_id AS id_job,
    current_stage_id AS id_current_stage,
    source_member_id AS id_source_member,
    recommender_id AS id_recommender,
    recruiter_id AS id_recruiter,
    uploader_id AS id_uploader,
    api_id AS id_api,
    -- non-metrics
    job_title,
    job_department,
   `name`,
    firstname AS first_name,
    lastname AS last_name,
    headline,
    email,
    application_method,
    source_category,
    source_domain,
    `source`,
    outlet,
    current_stage_name,
    disqualification_reason,
    metadata,
    tags,
    linkedin_profile_url,
    -- metrics
    copied AS is_copied,
    disqualified AS is_disqualified,
    recommended AS is_recommended,
    snoozed AS is_snoozed,
    -- timestamps
    candidate_created_at AS ts_candidate_created,
    job_first_published_at AS ts_job_first_published, 
    last_unanswered_email_at AS ts_last_unanswered_email,
    first_screened_at AS ts_first_screen,
    first_contacted_at AS ts_first_contact,
    first_interviewed_at AS ts_first_interview,
    first_offer_at AS ts_first_offer,
    first_hired_at AS ts_first_hire,
    disqualified_at AS ts_disqualified,
    snoozed_until AS ts_snoozed_until,
    updated_at AS ts_updated,
    NOW() AS ts_load
FROM
    datalake_workable_redshift_raw.candidates
WHERE  
    MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')