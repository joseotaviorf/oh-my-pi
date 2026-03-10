WITH
terminations AS (
    SELECT
        aa.id_assignment,
        aa.action_code,
        aa.reason_code,
        al.description AS dismissal_type,
        art.action_reason AS dismissal_reason
    FROM
        datalake_pin_core_clean.all_assignments AS aa
    LEFT JOIN
        datalake_hr_system_clean.actions_lov AS al
        ON al.action_code = aa.action_code
    LEFT JOIN
        datalake_pin_core_clean.action_reason_base AS arb
        ON arb.action_reason_code = aa.reason_code
    LEFT JOIN
        datalake_pin_core_clean.action_reason_translation AS art
        ON art.id_action_reason = arb.id_action_reason
        AND art.language = 'PTB'
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
    QUALIFY
        ROW_NUMBER() OVER (
            PARTITION BY id_assignment
            ORDER BY dt_effective_started DESC
        ) = 1
)
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
    NOW() AS ts_load
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
QUALIFY
    ROW_NUMBER() OVER (PARTITION BY im.id_assignment ORDER BY im.dt_started DESC NULLS LAST) = 1