WITH base_jobs AS (
	SELECT
		*,
        (ts_created + interval 30 days) as ts_created_extended,
		row_number() OVER (PARTITION BY id_house ORDER BY ts_created) AS rn
	FROM
		datalake_ebdb_listing_jobs.photo_job
)
SELECT -- [ODS] This table was migrated from ODS flow and needs a future refactoring to remove castings and renamings
	j.id AS sk_photo_job,
	j.id,
	j.id_house AS imovel_id,
	j.id_rep AS rep_id,
	j.id_photographer AS photographer_id,
	j.id_user_who_canceled AS user_cancel_id,
	j.job_status,
	j.creation_origin,
	LEFT(NULLIF(j.booking_instructions, ''), 100) as scheduling_instructions,
	j.photo_session_contact_name AS photo_shoot_contact_name,
	j.photo_session_email AS photo_shoot_email,
	j.photo_session_phone AS photo_shoot_phone,
	NULLIF(j.photo_session_secondary_phone, '') AS photo_shoot_second_phone,
	j.key_pick_up AS key_withdraw,
	LEFT(NULLIF(j.key_others, ''), 255) as key_comments,
	j.photographer_name AS photographer_name,
	j.photographer_email AS photographer_email,
	j.contract_type AS photographer_contract_type,
	j.problem AS photographer_problem_reason,
	j.photo_sender_user_type AS user_sender_type,
	LEFT(NULLIF(j.cancellation_reason, ''), 100) AS cancel_reason,
	LEFT(NULLIF(j.cancellation_reason_text, ''), 400) AS cancel_reason_detailed,
	j.user_who_canceled_name AS user_cancel_name,
	j.user_who_canceled_email AS user_cancel_email,
	j.user_cancellation_type AS user_cancel_type,
	CAST(j.is_flexible_schedule AS INT) AS flexible_schedule,
	CAST(j.is_approved AS INT) AS approved,
	CAST(j.is_confirmed AS INT) AS confirmed,
	CAST(j.has_lockbox AS INT) AS lockbox,
	(job_rescheduled_to.id IS NOT NULL) as rescheduled,
    j.is_same_day_upload,
	j.is_job_anticipated AS is_anticipated,
	j.ts_photographer_accepted AS dt_photographer_accepted,
	j.ts_created AS dt_job_created,
	j.ts_photo_job_requested AS dt_job_issued,
	j.ts_session_started AS dt_shoot_started,
	j.ts_scheduled AS dt_job_scheduled,
	j.ts_photos_uploaded AS dt_photos_uploaded,
	j.ts_updated AS dt_updated,
	j.ts_canceled AS dt_problem_reported,
	j.dt_photographer_started AS dt_photographer_start,
	j.ts_problem_reported AS user_cancel_dt,
	-- Applying FLOOR function to match ODS
	CAST(FLOOR(j.creation_to_scheduling_diff_minutes) AS DECIMAL(10,1)) AS creation_to_scheduling_diff_minutes,
	CAST(ROUND(FLOOR(j.creation_to_scheduling_diff_minutes) / 60, 1) AS DECIMAL(10,1)) AS creation_to_scheduling_diff_hours,
	CAST(ROUND(FLOOR(j.creation_to_scheduling_diff_minutes) / 1440, 1) AS DECIMAL(10,1)) AS creation_to_scheduling_diff_days
FROM
	base_jobs j
LEFT JOIN
	base_jobs job_rescheduled_to
	ON j.id_house = job_rescheduled_to.id_house
	AND j.rn = job_rescheduled_to.rn -1
	AND j.ts_created_extended > job_rescheduled_to.ts_created