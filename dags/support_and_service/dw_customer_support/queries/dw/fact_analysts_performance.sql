WITH recontact_data AS (
    SELECT
        ut.id_ticket,
        IF(tf.ts_updated > ut.ts_solved, TRUE, FALSE) AS is_recontact_ticket
    FROM
        datalake_customer_support.unified_tickets AS ut
    LEFT JOIN
        datalake_zendesk.tickets_current AS tf
            ON ut.id_ticket = tf.id_ticket
    WHERE
        DATE(ut.ts_solved) = MAKE_DATE({year}, {month}, {day})
    QUALIFY
        ROW_NUMBER() OVER (PARTITION BY ut.id_ticket ORDER BY tf.ts_updated DESC) = 1
),
without_agg_infos AS (
    SELECT
        ut.id_ticket,
        id_last_agent AS id_agent,
        dc.team,
        rd.status,
        ut.resolution_survey,
        ut.reopens AS reopened_tickets,
        ut.replies AS replied_tickets,
        ut.first_csat_score AS first_csat_score,
        DATEDIFF(ut.ts_solved, ut.ts_started) AS attendance_time,
        r.is_recontact_ticket,
        IF(DATE(ut.ts_solved) = MAKE_DATE({year}, {month}, {day}) OR DATE(ut.ts_closed) = MAKE_DATE({year}, {month}, {day}), TRUE, FALSE) AS is_received_demand,
        IF(DATE(ut.ts_solved) = MAKE_DATE({year}, {month}, {day}), TRUE, FALSE) AS is_productive_ticket,
        CASE
            WHEN ROW_NUMBER() OVER(PARTITION BY MD5(
              COALESCE(CONCAT(rd.id_call, 'call'),
              CONCAT(rd.id_session, 'chat'),
              CONCAT(rd.id_ticket, 'email'))
            ), rd.department ORDER BY rd.ts_created) = 1 THEN TRUE
            ELSE FALSE
        END AS is_first_department_interaction,
        bmt.is_backlog_in_time,
        bmt.is_backlog_not_in_time,
        IF(bmt.is_backlog_in_time OR bmt.is_backlog_not_in_time, TRUE, FALSE) AS is_backlog,
        ut.ts_csat_response,
        DATE(tf.ts_updated) AS dt_last_ticket_updated
    FROM
        datalake_customer_support.unified_tickets AS ut
    INNER JOIN
        datalake_zendesk.tickets_current AS tf
            ON ut.id_ticket = tf.id_ticket
    LEFT JOIN
        datalake_customer_support.received_demand AS rd
            ON ut.id_ticket = rd.id_ticket
    LEFT JOIN
        datalake_customer_demand.backlog_metrics_tasks AS bmt
            ON ut.id_ticket = bmt.id_task
    LEFT JOIN
        datalake_gsheets_clean.department_control AS dc
            ON ut.id_main_department = MD5(dc.department)
    LEFT JOIN
        recontact_data AS r
            ON ut.id_ticket = r.id_ticket
    WHERE
        ut.front_or_back <> "undefined"
        AND dc.team IS NOT NULL
        AND DATE(tf.ts_updated) = MAKE_DATE({year}, {month}, {day})
    QUALIFY
        ROW_NUMBER() OVER (PARTITION BY ut.id_ticket ORDER BY tf.ts_updated DESC) = 1
)
SELECT
    wa.id_agent || dt_last_ticket_updated AS sk_snapshot,
    wa.id_agent AS sk_agent,
    COALESCE(CAST(DATE_FORMAT(wa.dt_last_ticket_updated,'yyyyMMdd') AS BIGINT), -1) AS sk_last_ticket_updated_date,
    COUNT(id_ticket) AS total_tickets,
    SUM(wa.reopened_tickets) AS ticket_reopenings,
    SUM(wa.replied_tickets) AS ticket_responses,
    SUM(wa.attendance_time) AS total_attendance_time,
    COUNT_IF(wa.is_recontact_ticket = TRUE) AS total_tickets_recontact,
    COUNT_IF(wa.is_received_demand = TRUE) AS total_received_demand,
    COUNT_IF(wa.is_productive_ticket = TRUE) AS total_productivity,
    COUNT(
        CASE
            WHEN
                wa.first_csat_score IS NOT NULL
                THEN wa.id_ticket
            ELSE NULL
        END
    ) AS tickets_with_csat_score,
    COUNT(
        CASE
            WHEN
                wa.first_csat_score IN (4,5)
                THEN wa.id_ticket
            ELSE NULL
        END
    ) AS tickets_csat_satisfied,
    COUNT(
        CASE
            WHEN
                wa.first_csat_score = 3
                THEN wa.id_ticket
            ELSE NULL
        END
    ) AS tickets_csat_neutral,
    COUNT(
        CASE
            WHEN
                wa.first_csat_score IN (1,2)
                THEN wa.id_ticket
            ELSE NULL
        END
    ) AS tickets_csat_dissatisfied,
    COUNT(
        CASE
            WHEN
                wa.resolution_survey IS NOT NULL
                OR wa.ts_csat_response IS NOT NULL
                THEN wa.id_ticket
        END
    ) AS tickets_with_resolution_answered,
    COUNT(
        CASE
            WHEN
                wa.resolution_survey = True
                OR wa.ts_csat_response IS NOT NULL
                THEN wa.id_ticket
        END
    ) AS tickets_with_resolution,
    COUNT(
        CASE
            WHEN wa.status = 'TRANSFERRED'
            AND wa.is_first_department_interaction = True
            AND wa.team <> 'Inside Sales'
            THEN wa.id_ticket
            ELSE NULL
        END
    ) AS tickets_transferred,
    COUNT_IF(wa.is_backlog = TRUE) AS tickets_in_backlog,
    COUNT_IF(wa.is_backlog_in_time = TRUE) AS backlog_within_sla,
    COUNT_IF(wa.is_backlog_not_in_time = TRUE) AS backlog_with_exceed_sla,
    YEAR(wa.dt_last_ticket_updated) AS year,
    MONTH(wa.dt_last_ticket_updated) AS month,
    DAY(wa.dt_last_ticket_updated) AS day
FROM
    without_agg_infos AS wa
GROUP BY
    2, dt_last_ticket_updated
