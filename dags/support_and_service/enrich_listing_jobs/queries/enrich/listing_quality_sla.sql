WITH completed_job AS (
    SELECT
        id_house,
        DATE(ts_photos_uploaded - INTERVAL 1 HOUR) AS dt_uploaded,
        DATEDIFF(LEAD(DATE(ts_photos_uploaded - INTERVAL 1 HOUR)) OVER (PARTITION BY id_house ORDER BY DATE(ts_photos_uploaded - INTERVAL 1 HOUR) ASC), DATE(ts_photos_uploaded - INTERVAL 1 HOUR)) AS diff
    FROM
        datalake_ebdb_photo_jobs.photo_job
    WHERE
        DATE(ts_photos_uploaded - INTERVAL 1 HOUR) >= DATE('2023-01-01')
        AND job_status IN ('Completado', 'Publicado')
),
remove_duplicates AS (
    SELECT
        id_house,
        dt_uploaded,
        ROW_NUMBER() OVER (PARTITION BY id_house ORDER BY dt_uploaded ASC) AS rk1
    FROM
        completed_job
    WHERE
        diff IS NULL
        OR diff > 2
),
listing_quality_tasks AS (
    SELECT
        tf.id_ticket,
        REGEXP_EXTRACT(tf.subject, '(\\d+)', 0) AS id_house,
        tf.agent_organization,
        tf.ts_created_local,
        tfm.ts_solved_local,
        RANK() OVER (PARTITION BY REGEXP_EXTRACT(tf.subject, '(\\d+)', 0) ORDER BY tfm.ts_solved_local ASC) AS rk2
    FROM
        datalake_zendesk_ticket_funnels.ticket_funnel AS tf
    LEFT JOIN
        datalake_zendesk_ticket_funnels.tickets_funnel_metrics AS tfm
            ON tf.id_ticket = tfm.id_ticket
    WHERE
        tf.group_name = 'Listing Quality [FOTOS] [SO]'
        AND tf.status IN ('solved', 'closed')
),
general_base AS (
    SELECT
        MD5(jb.id_house || lqt.id_ticket || jb.dt_uploaded) AS id_listing_quality_sla,
        CONCAT(jb.id_house, '|', lqt.id_ticket, '|', jb.dt_uploaded) AS business_key,
        lqt.id_ticket,
        jb.id_house,
        lqt.agent_organization,
        IF(jb.id_house IS NOT NULL, TRUE, FALSE) AS has_demand,
        IF(lqt.id_ticket IS NOT NULL, TRUE, FALSE) AS has_task_done,
        IF(ww.dt_end_1 >= DATE(lqt.ts_solved_local), TRUE, FALSE) AS has_sla_achieved,
        IF((
            ww.dt_end_1 <= (CURRENT_DATE - INTERVAL 1 DAY) AND DATE(lqt.ts_solved_local) IS NULL),
            TRUE,
            FALSE
        ) AS has_backlog,
        IF(v.id_source IS NOT NULL, TRUE, FALSE) AS has_video,
        jb.dt_uploaded,
        DATE(lqt.ts_created_local) AS dt_ticket_created,
        DATE(lqt.ts_solved_local) AS dt_ticket_solved
    FROM
        remove_duplicates AS jb
    LEFT JOIN
        listing_quality_tasks AS lqt
            ON lqt.id_house = jb.id_house
            AND lqt.rk2 = jb.rk1
    LEFT JOIN
        datalake_date.workday_window AS ww
            ON ww.dt_ref = jb.dt_uploaded
            AND ww.id_city = 39
    LEFT JOIN
        datalake_kodak_clean.video AS v
            ON jb.id_house = v.id_external_domain
    WHERE
        jb.dt_uploaded BETWEEN DATE('2023-01-01') AND (CURRENT_DATE - INTERVAL 1 DAY)
)
SELECT
    *
FROM
    general_base
QUALIFY
    ROW_NUMBER() OVER (PARTITION BY id_house, id_ticket ORDER BY dt_uploaded DESC) = 1
