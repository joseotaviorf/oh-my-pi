WITH photo_jobs AS (
    SELECT
        imovel_id,
        sk_photo_job,
        job_status,
        creation_origin,
        cancel_reason,
        photographer_problem_reason,
        user_cancel_type,
        dt_job_created,
        dt_job_scheduled,
        user_cancel_dt,
        job_status IN ('Publicado', 'Completado', 'FotosTiradas') AS is_converted
    FROM dw_public.dim_photo_job
),

base_agg AS (
    SELECT
        imovel_id,
        min_by(sk_photo_job, ROW(dt_job_created, sk_photo_job))     AS id_first_photo_job,
        max_by(sk_photo_job, ROW(dt_job_created, sk_photo_job))     AS id_last_photo_job,
        min_by(creation_origin, ROW(dt_job_created, sk_photo_job))  AS creation_origin_first_schedule,
        max_by(creation_origin, ROW(dt_job_created, sk_photo_job))  AS creation_origin_last_schedule,
        max_by(job_status, ROW(dt_job_created, sk_photo_job))       AS status_last_photo_job,
        MIN(dt_job_created)                                         AS dt_first_job_created,
        COUNT(DISTINCT sk_photo_job)                               AS qty_schedules,
        bool_or(is_converted)                                      AS has_successful_job,
        MIN(IF(is_converted, dt_job_created))                      AS dt_first_successful_job,
        min_by(dt_job_scheduled, IF(is_converted, dt_job_created)) AS dt_first_converted_scheduled,
        max_by(creation_origin, IF(is_converted, dt_job_created))  AS creation_origin_converted_listing,
        COUNT_IF(user_cancel_type = 'Prop')                        AS qty_cancel_by_owner,
        COUNT_IF(user_cancel_type = 'Fotografo')                   AS qty_cancel_by_photographer
    FROM photo_jobs
    GROUP BY imovel_id
),

consecutive_gaps AS (
    SELECT
        imovel_id,
        GREATEST(
            DATE_DIFF(
                'day',
                LAG(user_cancel_dt) OVER (PARTITION BY imovel_id ORDER BY dt_job_created ASC, sk_photo_job ASC),
                dt_job_created
            ),
            0
        ) AS days_since_previous_job  -- prev scheduling's cancel date -> new job's creation date; floored at 0
    FROM photo_jobs
),
reschedule_intervals AS (
    SELECT
        imovel_id,
        MIN(days_since_previous_job) AS min_days_between_reschedules,
        MAX(days_since_previous_job) AS max_days_between_reschedules
    FROM consecutive_gaps
    WHERE days_since_previous_job IS NOT NULL
    GROUP BY imovel_id
),

-- Most frequent cancel reason (photographer problem OR cancel reason) + distinct count.
cancel_reason_counts AS (
    SELECT
        imovel_id,
        COALESCE(photographer_problem_reason, cancel_reason) AS cancel_reason_combined,
        COUNT(*) AS reason_count
    FROM photo_jobs
    WHERE COALESCE(photographer_problem_reason, cancel_reason) IS NOT NULL
    GROUP BY imovel_id, COALESCE(photographer_problem_reason, cancel_reason)
),
cancel_reason_agg AS (
    SELECT
        imovel_id,
        max_by(cancel_reason_combined, reason_count) AS most_frequent_cancel_reason,
        COUNT(*)                                     AS distinct_cancel_reason_count
    FROM cancel_reason_counts
    GROUP BY imovel_id
),

-- Most frequent photographer_problem_reason (only photographer-side problems).
photographer_problem_counts AS (
    SELECT
        imovel_id,
        photographer_problem_reason,
        COUNT(*) AS problem_count
    FROM photo_jobs
    WHERE photographer_problem_reason IS NOT NULL
    GROUP BY imovel_id, photographer_problem_reason
),
photographer_problem_agg AS (
    SELECT
        imovel_id,
        max_by(photographer_problem_reason, problem_count) AS most_frequent_photographer_problem_reason
    FROM photographer_problem_counts
    GROUP BY imovel_id
),

-- Most frequent cancel user type.
cancel_user_type_counts AS (
    SELECT
        imovel_id,
        user_cancel_type,
        COUNT(*) AS user_type_count
    FROM photo_jobs
    WHERE user_cancel_type IS NOT NULL
    GROUP BY imovel_id, user_cancel_type
),
cancel_user_type_agg AS (
    SELECT
        imovel_id,
        max_by(user_cancel_type, user_type_count) AS most_frequent_cancel_user_type
    FROM cancel_user_type_counts
    GROUP BY imovel_id
),

-- Per-house obt_supply facts in ONE scan (opportunity + first_listing rows only):
--  * opportunity_channel / planning_operation: from the earliest 'opportunity' row
--    (min_by with a NULL key on non-opportunity rows, which are ignored).
--  * has_first_listing / dt_first_listing: presence and earliest date of any
--    'first_listing' row for the house.
obt_agg AS (
    SELECT
        sk_house AS imovel_id,
        min_by(tp_origin_conversion, IF(cd_funnel_step = 'opportunity', "date")) AS opportunity_channel,
        min_by(planning_operation,   IF(cd_funnel_step = 'opportunity', "date")) AS planning_operation,
        bool_or(cd_funnel_step = 'first_listing')                                AS has_first_listing,
        MIN(IF(cd_funnel_step = 'first_listing', "date"))                        AS dt_first_listing
    FROM dw_growth.obt_supply
    WHERE cd_funnel_step IN ('opportunity', 'first_listing')
    GROUP BY sk_house
)

SELECT
    b.imovel_id,
    b.id_first_photo_job,
    b.id_last_photo_job,
    b.dt_first_job_created,
    oa.opportunity_channel,
    oa.planning_operation,
    COALESCE(oa.has_first_listing, FALSE) AS has_first_listing,
    oa.dt_first_listing,
    b.creation_origin_first_schedule,
    b.creation_origin_last_schedule,
    b.qty_schedules,
    b.has_successful_job,
    b.dt_first_successful_job,
    b.creation_origin_converted_listing,
    b.status_last_photo_job,
    ri.min_days_between_reschedules,
    ri.max_days_between_reschedules,
    DATE_DIFF('day', b.dt_first_job_created, b.dt_first_converted_scheduled) AS leadtime_days_first_schedule_to_conversion,
    b.qty_cancel_by_owner,
    b.qty_cancel_by_photographer,
    cra.most_frequent_cancel_reason,
    cra.distinct_cancel_reason_count,
    ppa.most_frequent_photographer_problem_reason,
    cua.most_frequent_cancel_user_type
FROM base_agg b
LEFT JOIN obt_agg oa                   ON b.imovel_id = oa.imovel_id
LEFT JOIN reschedule_intervals ri      ON b.imovel_id = ri.imovel_id
LEFT JOIN cancel_reason_agg cra        ON b.imovel_id = cra.imovel_id
LEFT JOIN photographer_problem_agg ppa ON b.imovel_id = ppa.imovel_id
LEFT JOIN cancel_user_type_agg cua     ON b.imovel_id = cua.imovel_id
WHERE b.dt_first_job_created >= DATE '2026-01-01'
