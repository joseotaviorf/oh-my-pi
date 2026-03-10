WITH distinct_event_definition AS (
    SELECT DISTINCT
        id_action,
        id_action_reason
    FROM
        datalake_pin_core_clean.action_occurrence
)
SELECT
    -- IDs
    CONCAT(
        CAST(ded.id_action AS STRING),
        '-',
        CAST(ded.id_action_reason AS STRING)
    ) AS id_event_definition,
    ded.id_action,
    ded.id_action_reason AS id_reason,
    -- Codes
    ab.action_code,
    arb.action_reason_code AS reason_code,
    -- English
    at_us.action_name,
    art_us.action_reason AS reason_name,
    at_us.description AS action_description,
    -- Portuguese
    at_ptb.action_name AS action_name_ptb,
    art_ptb.action_reason AS reason_name_ptb,
    at_ptb.description AS action_description_ptb,
    -- Booleans
    CASE
        WHEN GREATEST(ab.dt_started, arb.dt_started) <= CURRENT_DATE()
            AND (ab.dt_ended IS NULL OR ab.dt_ended >= DATE('4712-12-31') OR ab.dt_ended > CURRENT_DATE())
            AND (arb.dt_ended IS NULL OR arb.dt_ended >= DATE('4712-12-31') OR arb.dt_ended > CURRENT_DATE())
        THEN TRUE
        ELSE FALSE
    END AS is_current,
    -- Dates
    GREATEST(ab.dt_started, arb.dt_started) AS dt_valid_from,
    CASE
        WHEN ab.dt_ended IS NULL OR ab.dt_ended >= DATE('4712-12-31')
        THEN arb.dt_ended
        WHEN arb.dt_ended IS NULL OR arb.dt_ended >= DATE('4712-12-31')
        THEN ab.dt_ended
        ELSE LEAST(ab.dt_ended, arb.dt_ended)
    END AS dt_valid_to,
    ab.dt_started AS dt_action_started,
    ab.dt_ended AS dt_action_ended,
    arb.dt_started AS dt_reason_started,
    arb.dt_ended AS dt_reason_ended,
    NOW() AS ts_load
FROM
    distinct_event_definition AS ded
INNER JOIN
    datalake_pin_core_clean.action_base AS ab
        ON ab.id_action = ded.id_action
INNER JOIN
    datalake_pin_core_clean.action_reason_base AS arb
        ON arb.id_action_reason = ded.id_action_reason
LEFT JOIN
    datalake_pin_core_clean.action_translation AS at_us
        ON at_us.id_action = ded.id_action
        AND at_us.language = 'US'
LEFT JOIN
    datalake_pin_core_clean.action_reason_translation AS art_us
        ON art_us.id_action_reason = ded.id_action_reason
        AND art_us.language = 'US'
LEFT JOIN
    datalake_pin_core_clean.action_translation AS at_ptb
        ON at_ptb.id_action = ded.id_action
        AND at_ptb.language = 'PTB'
LEFT JOIN
    datalake_pin_core_clean.action_reason_translation AS art_ptb
        ON art_ptb.id_action_reason = ded.id_action_reason
        AND art_ptb.language = 'PTB'
