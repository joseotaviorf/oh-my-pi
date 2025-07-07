WITH base_jobs AS (
	SELECT
		*,
        (ts_created + interval 30 days) as ts_created_extended,
		row_number() OVER (PARTITION BY id_house ORDER BY ts_created) AS rn
	FROM
		datalake_ebdb_photo_jobs.photo_job
)
SELECT
    j.id AS id_photo_job,
    -- There is already the 'hl.id_house_listing' that has a similar rule to the below,
    --  however it does not cover NULL cases, so we replicated the ODS concatenation here
    -- to be one hundred percent compliant to the original rule
    CAST(
        (
            (j.id_house || '00')
            ||
            (CAST(COALESCE(hl.version, 0) AS VARCHAR(24)))
        ) AS BIGINT) AS sk_house_listing,
    COALESCE(house.id_region, -1) AS sk_region,
    COALESCE(j.id_user_who_canceled, -1) AS sk_user_cancel,
    COALESCE(j.id_photographer, -1) AS sk_user_photographer,
    COALESCE(j.id_rep, -1) AS sk_user_rep,
    j.job_status AS job_status,
    j.creation_origin AS creation_origin,
    j.photo_session_contact_name AS photo_shoot_contact_name,
    j.photo_session_email AS photo_shoot_email,
    j.photo_session_phone AS photo_shoot_phone,
    NULLIF(j.photo_session_secondary_phone, '') AS photo_shoot_second_phone,
    j.key_pick_up AS key_withdraw,
    LEFT(NULLIF(j.key_others, ''), 100) AS key_comments,
    j.contract_type AS photographer_contract_type,
    j.problem AS photographer_problem_reason,
    LEFT(NULLIF(j.cancellation_reason, ''), 100) AS cancel_reason,
    j.user_cancellation_type AS user_cancel_type,
    CAST(j.is_flexible_schedule AS INTEGER) AS flexible_schedule,
    j.is_same_day_upload AS is_same_day_upload,
    j.is_job_anticipated AS is_anticipated,
    j.is_job_on_time AS flg_job_on_time,
    CAST(j.is_approved AS INTEGER) AS approved,
    CAST(j.is_confirmed AS INTEGER) AS confirmed,
    CAST(j.has_lockbox AS INTEGER) AS lockbox,
    (job_rescheduled_to.id IS NOT NULL) AS rescheduled,
    COALESCE(CAST(DATE_FORMAT(CAST(j.ts_photographer_accepted AS DATE),'yyyyMMdd') AS INTEGER), -1) AS sk_date_photographer_accepted,
    COALESCE(CAST(DATE_FORMAT(CAST(j.ts_created AS DATE),'yyyyMMdd') AS INTEGER), -1) AS sk_date_job_created,
    COALESCE(CAST(DATE_FORMAT(CAST(j.ts_photo_job_requested AS DATE),'yyyyMMdd') AS INTEGER), -1) AS sk_date_job_issued,
    COALESCE(CAST(DATE_FORMAT(CAST(j.ts_session_started AS DATE),'yyyyMMdd') AS INTEGER), -1) AS sk_date_shoot_started,
    COALESCE(CAST(DATE_FORMAT(CAST(j.ts_scheduled AS DATE),'yyyyMMdd') AS INTEGER), -1) AS sk_date_job_scheduled,
    COALESCE(CAST(DATE_FORMAT(CAST(j.ts_photos_uploaded AS DATE),'yyyyMMdd') AS INTEGER), -1) AS sk_date_photos_uploaded,
    COALESCE(CAST(DATE_FORMAT(CAST(j.ts_updated AS DATE),'yyyyMMdd') AS INTEGER), -1) AS sk_date_updated,
    COALESCE(CAST(DATE_FORMAT(CAST(j.dt_photographer_started AS DATE),'yyyyMMdd') AS INTEGER), -1) AS sk_date_photographer_start,
    -- The following two columns are misleading, since the enrich name is diff from the one from ods
    COALESCE(CAST(DATE_FORMAT(CAST(j.ts_problem_reported AS DATE),'yyyyMMdd') AS INTEGER), -1) AS sk_date_user_cancel,
    COALESCE(CAST(DATE_FORMAT(CAST(j.ts_canceled AS DATE),'yyyyMMdd') AS INTEGER), -1) AS sk_date_problem_reported,
    -- Applying FLOOR function to match ODS
	CAST(FLOOR(j.creation_to_scheduling_diff_minutes) AS DECIMAL(10,1)) AS creation_to_scheduling_diff_minutes,
    CAST(ROUND(FLOOR(j.creation_to_scheduling_diff_minutes) / 60, 1) AS DECIMAL(10,1)) AS creation_to_scheduling_diff_hours,
    CAST(ROUND(FLOOR(j.creation_to_scheduling_diff_minutes) / 1440, 1) AS DECIMAL(10,1)) AS creation_to_scheduling_diff_days,
    NOW() AS ts_load
FROM
	base_jobs j
LEFT JOIN
	base_jobs job_rescheduled_to
	ON j.id_house = job_rescheduled_to.id_house
	AND j.rn = job_rescheduled_to.rn -1
	AND j.ts_created_extended > job_rescheduled_to.ts_created
LEFT JOIN
    datalake_ebdb_clean.house house
    ON house.id = j.id_house
LEFT JOIN
    datalake_ebdb_listing.house_listing hl
    ON hl.id_house = j.id_house
    AND j.ts_created BETWEEN hl.ts_listing_version_start AND COALESCE(hl.ts_listing_version_end, NOW())
