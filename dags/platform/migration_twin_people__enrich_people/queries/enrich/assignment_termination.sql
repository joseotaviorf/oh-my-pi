WITH
terminations_ranked AS (
    SELECT
        aa.id_assignment,
        aa.action_code,
        aa.reason_code,
        COALESCE(
            NULLIF(TRIM(at.description), ''),
            at.action_name
        ) AS dismissal_type,
        art.action_reason AS dismissal_reason,
        ROW_NUMBER() OVER (
            PARTITION BY aa.id_assignment
            ORDER BY aa.dt_effective_started DESC
        ) AS rn
    FROM
        datalake_pin_core_clean.all_assignments AS aa
    LEFT JOIN
        datalake_pin_core_clean.action_base AS ab
            ON ab.action_code = aa.action_code
            AND ab.id_business_group = aa.id_business_group
            AND ab.dt_ended = DATE('9999-12-31')
    LEFT JOIN
        datalake_pin_core_clean.action_translation AS at
            ON at.id_action = ab.id_action
            AND at.id_business_group = ab.id_business_group
            AND at.language = 'US'
    LEFT JOIN
        datalake_pin_core_clean.action_reason_base AS arb
            ON arb.action_reason_code = aa.reason_code
    LEFT JOIN
        datalake_pin_core_clean.action_reason_translation AS art
            ON art.id_action_reason = arb.id_action_reason
            AND art.language = 'US'
    WHERE
        aa.is_primary
        AND aa.assignment_type IN ('E', 'C')
        AND aa.action_code IN (
            'TERMINATION',
            'RESIGNATION',
            'DEATH',
            'GLB_TRANSFER',
            'EXPATRIADO'
        )
        AND aa.assignment_status_type = 'INACTIVE'
),
terminations AS (
    SELECT
        id_assignment,
        action_code,
        reason_code,
        dismissal_type,
        dismissal_reason
    FROM
        terminations_ranked
    WHERE
        rn = 1
),
deduplicated AS (
    SELECT
        im.id_assignment,
        im.person_number,
        im.assignment_number,
        im.dt_started AS dt_hired,
        im.dt_notified_termination AS dt_notified,
        im.dt_actual_termination AS dt_terminated,
        t.action_code,
        t.reason_code,
        t.dismissal_type,
        t.dismissal_reason,
        NOW() AS ts_load,
        ROW_NUMBER() OVER (
            PARTITION BY im.id_assignment
            ORDER BY im.dt_started DESC NULLS LAST
        ) AS rn
    FROM
        datalake_people.identifier_mapping AS im
    LEFT JOIN
        terminations AS t
            ON t.id_assignment = im.id_assignment
    WHERE
        im.assignment_type IN ('E', 'C')
        AND (
            im.dt_actual_termination IS NOT NULL
            OR im.dt_notified_termination IS NOT NULL
        )
)
SELECT
    id_assignment,
    person_number,
    assignment_number,
    dt_hired,
    dt_notified,
    dt_terminated,
    action_code,
    reason_code,
    dismissal_type,
    dismissal_reason,
    ts_load
FROM
    deduplicated
WHERE
    rn = 1
