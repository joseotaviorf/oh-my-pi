WITH visitor_visits AS (
    SELECT
        id_user,
        uuid_person,
        id_house,
        id_entity AS visit_code,
        persona,
        business_context,
        is_active,
        GET_JSON_OBJECT(properties, '$.what') AS visit_status,
        TRY_CAST(GET_JSON_OBJECT(properties, '$.when') AS TIMESTAMP) AS ts_visit_when,
        ts_created,
        ts_updated
    FROM
        datalake_transactional_entities.entities
    WHERE
        entity = 'VISIT'
        AND persona IN ('TENANT_PROSPECT', 'BUYER_PROSPECT')
        AND id_user IS NOT NULL
),
next_visit AS (
    SELECT
        ranked.id_user,
        ranked.id_house AS id_house_next_visit,
        ranked.visit_code AS visit_code_next,
        ranked.ts_visit_when AS ts_next_visit
    FROM (
        SELECT
            id_user,
            id_house,
            visit_code,
            ts_visit_when,
            ROW_NUMBER() OVER (
                PARTITION BY id_user
                ORDER BY ts_visit_when ASC
            ) AS rn
        FROM
            visitor_visits
        WHERE
            is_active = TRUE
            AND ts_visit_when IS NOT NULL
            AND DATE(ts_visit_when) >= CURRENT_DATE()
    ) AS ranked
    WHERE
        ranked.rn = 1
),
last_canceled_1d AS (
    SELECT
        ranked.id_user,
        ranked.id_house AS id_house_last_canceled_1d,
        ranked.visit_code AS visit_code_last_canceled_1d
    FROM (
        SELECT
            id_user,
            id_house,
            visit_code,
            ROW_NUMBER() OVER (
                PARTITION BY id_user
                ORDER BY ts_updated DESC, visit_code DESC
            ) AS rn
        FROM
            visitor_visits
        WHERE
            visit_status = 'VISIT_CANCELED'
            AND DATE(ts_updated) = DATE_ADD(CURRENT_DATE(), -1)
    ) AS ranked
    WHERE
        ranked.rn = 1
),
visit_counts AS (
    SELECT
        id_user,
        COUNT(DISTINCT CASE
            WHEN is_active = TRUE
                AND DATE(ts_visit_when) = DATE_ADD(CURRENT_DATE(), 1)
            THEN visit_code
        END) AS qty_visits_tomorrow,
        COUNT(DISTINCT CASE
            WHEN DATE(ts_visit_when) >= CURRENT_DATE()
                AND DATE(ts_visit_when) < DATE_ADD(CURRENT_DATE(), {days_lookback_7})
            THEN visit_code
        END) AS qty_visits_7d,
        COUNT(DISTINCT CASE
            WHEN visit_status = 'VISIT_CANCELED'
                AND DATE(ts_updated) = DATE_ADD(CURRENT_DATE(), -1)
            THEN visit_code
        END) AS qty_visits_canceled_1d,
        COUNT(DISTINCT CASE
            WHEN visit_status = 'VISIT_CANCELED'
                AND DATE(ts_updated) >= DATE_ADD(CURRENT_DATE(), -{days_lookback_7})
                AND DATE(ts_updated) < CURRENT_DATE()
            THEN visit_code
        END) AS qty_visits_canceled_7d,
        COUNT(DISTINCT CASE
            WHEN visit_status = 'VISIT_RESCHEDULED'
                AND DATE(ts_updated) = DATE_ADD(CURRENT_DATE(), -1)
            THEN visit_code
        END) AS qty_visits_rescheduled_1d,
        COUNT(DISTINCT CASE
            WHEN visit_status = 'VISIT_RESCHEDULED'
                AND DATE(ts_updated) >= DATE_ADD(CURRENT_DATE(), -{days_lookback_7})
                AND DATE(ts_updated) < CURRENT_DATE()
            THEN visit_code
        END) AS qty_visits_rescheduled_7d
    FROM
        visitor_visits
    GROUP BY
        id_user
),
open_or_done AS (
    SELECT
        id_user,
        CONCAT_WS(',', COLLECT_SET(CAST(id_house AS STRING))) AS array_id_house_visit_open_or_done
    FROM
        visitor_visits
    WHERE
        id_house IS NOT NULL
        AND (
            is_active = TRUE
            OR visit_status = 'VISIT_DONE'
        )
    GROUP BY
        id_user
),
person_by_user AS (
    SELECT
        ranked.id_user,
        ranked.uuid_person AS id_person
    FROM (
        SELECT
            id_user,
            uuid_person,
            ROW_NUMBER() OVER (
                PARTITION BY id_user
                ORDER BY ts_updated DESC, uuid_person DESC
            ) AS rn
        FROM
            visitor_visits
        WHERE
            uuid_person IS NOT NULL
    ) AS ranked
    WHERE
        ranked.rn = 1
)
SELECT
    visit_counts.id_user,
    person_by_user.id_person,
    visit_counts.qty_visits_tomorrow,
    visit_counts.qty_visits_7d,
    visit_counts.qty_visits_canceled_1d,
    visit_counts.qty_visits_canceled_7d,
    visit_counts.qty_visits_rescheduled_1d,
    visit_counts.qty_visits_rescheduled_7d,
    next_visit.id_house_next_visit,
    next_visit.visit_code_next,
    next_visit.ts_next_visit,
    last_canceled_1d.id_house_last_canceled_1d,
    last_canceled_1d.visit_code_last_canceled_1d,
    open_or_done.array_id_house_visit_open_or_done,
    YEAR(CURRENT_DATE()) AS year,
    MONTH(CURRENT_DATE()) AS month,
    DAY(CURRENT_DATE()) AS day
FROM
    visit_counts
LEFT JOIN
    next_visit
    ON visit_counts.id_user = next_visit.id_user
LEFT JOIN
    last_canceled_1d
    ON visit_counts.id_user = last_canceled_1d.id_user
LEFT JOIN
    open_or_done
    ON visit_counts.id_user = open_or_done.id_user
LEFT JOIN
    person_by_user
    ON visit_counts.id_user = person_by_user.id_user
