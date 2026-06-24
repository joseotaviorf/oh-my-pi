WITH distinct_event_definition AS (
    SELECT DISTINCT
        id_action,
        id_action_reason,
        id_business_group
    FROM
        datalake_pin_core_clean.action_occurrence
),
current_action_base_ranked AS (
    SELECT
        ab.id_action,
        ab.id_business_group,
        ab.action_code,
        ab.dt_started,
        ab.dt_ended,
        ROW_NUMBER() OVER (
            PARTITION BY
                ab.id_action,
                ab.id_business_group
            ORDER BY
                CASE
                    WHEN
                        ab.dt_ended IS NULL
                        OR ab.dt_ended >= DATE('9999-12-31')
                        OR ab.dt_ended > CURRENT_DATE()
                    THEN 1
                    ELSE 0
                END DESC,
                ab.dt_started DESC
        ) AS rn
    FROM
        datalake_pin_core_clean.action_base AS ab
),
current_action_base AS (
    SELECT
        id_action,
        id_business_group,
        action_code,
        dt_started,
        dt_ended
    FROM
        current_action_base_ranked
    WHERE
        rn = 1
),
current_action_reason_base_ranked AS (
    SELECT
        arb.id_action_reason,
        arb.id_business_group,
        arb.action_reason_code,
        arb.dt_started,
        arb.dt_ended,
        ROW_NUMBER() OVER (
            PARTITION BY
                arb.id_action_reason,
                arb.id_business_group
            ORDER BY
                CASE
                    WHEN
                        arb.dt_ended IS NULL
                        OR arb.dt_ended >= DATE('9999-12-31')
                        OR arb.dt_ended > CURRENT_DATE()
                    THEN 1
                    ELSE 0
                END DESC,
                arb.dt_started DESC
        ) AS rn
    FROM
        datalake_pin_core_clean.action_reason_base AS arb
),
current_action_reason_base AS (
    SELECT
        id_action_reason,
        id_business_group,
        action_reason_code,
        dt_started,
        dt_ended
    FROM
        current_action_reason_base_ranked
    WHERE
        rn = 1
),
deduplicated AS (
    SELECT
        CONCAT(
            CAST(ded.id_action AS STRING),
            '-',
            CAST(ded.id_action_reason AS STRING)
        ) AS id_event_definition,
        ded.id_action,
        ded.id_action_reason AS id_reason,
        ab.action_code,
        arb.action_reason_code AS reason_code,
        at_us.action_name,
        art_us.action_reason AS reason_name,
        at_us.description AS action_description,
        at_ptb.action_name AS action_name_ptb,
        art_ptb.action_reason AS reason_name_ptb,
        at_ptb.description AS action_description_ptb,
        CASE
            WHEN GREATEST(ab.dt_started, arb.dt_started) <= CURRENT_DATE()
                AND (
                    ab.dt_ended IS NULL
                    OR ab.dt_ended >= DATE('9999-12-31')
                    OR ab.dt_ended > CURRENT_DATE()
                )
                AND (
                    arb.dt_ended IS NULL
                    OR arb.dt_ended >= DATE('9999-12-31')
                    OR arb.dt_ended > CURRENT_DATE()
                )
            THEN TRUE
            ELSE FALSE
        END AS is_current,
        GREATEST(ab.dt_started, arb.dt_started) AS dt_valid_from,
        CASE
            WHEN ab.dt_ended IS NULL OR ab.dt_ended >= DATE('9999-12-31')
            THEN arb.dt_ended
            WHEN arb.dt_ended IS NULL OR arb.dt_ended >= DATE('9999-12-31')
            THEN ab.dt_ended
            ELSE LEAST(ab.dt_ended, arb.dt_ended)
        END AS dt_valid_to,
        ab.dt_started AS dt_action_started,
        ab.dt_ended AS dt_action_ended,
        arb.dt_started AS dt_reason_started,
        arb.dt_ended AS dt_reason_ended,
        NOW() AS ts_load,
        ROW_NUMBER() OVER (
            PARTITION BY
                ded.id_action,
                ded.id_action_reason
            ORDER BY
                ded.id_business_group DESC
        ) AS rn
    FROM
        distinct_event_definition AS ded
    INNER JOIN
        current_action_base AS ab
            ON ab.id_action = ded.id_action
            AND ab.id_business_group = ded.id_business_group
    INNER JOIN
        current_action_reason_base AS arb
            ON arb.id_action_reason = ded.id_action_reason
            AND arb.id_business_group = ded.id_business_group
    LEFT JOIN
        datalake_pin_core_clean.action_translation AS at_us
            ON at_us.id_action = ded.id_action
            AND at_us.id_business_group = ded.id_business_group
            AND at_us.language = 'US'
    LEFT JOIN
        datalake_pin_core_clean.action_reason_translation AS art_us
            ON art_us.id_action_reason = ded.id_action_reason
            AND art_us.id_business_group = ded.id_business_group
            AND art_us.language = 'US'
    LEFT JOIN
        datalake_pin_core_clean.action_translation AS at_ptb
            ON at_ptb.id_action = ded.id_action
            AND at_ptb.id_business_group = ded.id_business_group
            AND at_ptb.language = 'PTB'
    LEFT JOIN
        datalake_pin_core_clean.action_reason_translation AS art_ptb
            ON art_ptb.id_action_reason = ded.id_action_reason
            AND art_ptb.id_business_group = ded.id_business_group
            AND art_ptb.language = 'PTB'
)
SELECT
    id_event_definition,
    id_action,
    id_reason,
    action_code,
    reason_code,
    action_name,
    reason_name,
    action_description,
    action_name_ptb,
    reason_name_ptb,
    action_description_ptb,
    is_current,
    dt_valid_from,
    dt_valid_to,
    dt_action_started,
    dt_action_ended,
    dt_reason_started,
    dt_reason_ended,
    ts_load
FROM
    deduplicated
WHERE
    rn = 1
