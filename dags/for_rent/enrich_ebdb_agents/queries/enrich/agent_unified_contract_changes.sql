WITH all_changes AS (
    SELECT
        id_agent,
        COALESCE(id_work_contract, -1) AS id_work_contract,
        COALESCE(id_previous_work_contract, -1) AS id_previous_work_contract,
        action AS ascc_action,
        NULL AS bcc_action,
        is_agent_active,
        NULL AS is_agent_for_sale,
        NULL AS is_agent_for_rent,
        has_changed_activated,
        has_changed_work_contract,
        NULL::BOOLEAN AS has_changed_business_context,
        ts_revision AS ts_status_started
    FROM
        datalake_ebdb_agents.agents_activations_suspensions_contracts_changes
    UNION ALL
    SELECT
        id_agent_data AS id_agent,
        NULL AS id_work_contract,
        NULL AS id_previous_work_contract,
        NULL AS ascc_action,
        'BUSINESS_CONTEXT_CHANGED' AS bcc_action,
        NULL AS is_agent_active,
        is_agent_for_sale,
        is_agent_for_rent,
        NULL::BOOLEAN AS has_changed_activated,
        NULL::BOOLEAN AS has_changed_work_contract,
        TRUE AS has_changed_business_context,
        ts_agent_business_context_started AS ts_status_started
    FROM
        datalake_ebdb_agents.agent_coincident_business_contexts
),
-- The business context can change simultaneously with the contract or the activation, and we don't want two
-- separate rows for that. Which is why we're grouping by agent and ts_status_started
unite_simultaneous_changes AS (
    SELECT
        id_agent,
        LAST(
            FIRST(id_work_contract, TRUE), -- This prioritizes the first non null value in the group by
            TRUE
        ) OVER ( -- And if it is still null, we will look back to previous lines to find the most recent non-null value
            PARTITION BY
                id_agent
            ORDER BY
                ts_status_started
        ) AS id_work_contract,
        LAST(
            FIRST(id_previous_work_contract, TRUE),
            TRUE
        ) OVER (
            PARTITION BY
                id_agent
            ORDER BY
                ts_status_started
        ) AS id_previous_work_contract,
        FIRST(ascc_action, TRUE) AS ascc_action,
        FIRST(bcc_action, TRUE) AS bcc_action,
        COALESCE(
            LAST(
                FIRST(is_agent_active, TRUE),
                TRUE
            ) OVER (
                PARTITION BY
                    id_agent
                ORDER BY
                    ts_status_started
            ),
            FALSE
        ) AS is_agent_active,
        COALESCE(
            LAST(
                FIRST(is_agent_for_sale, TRUE),
                TRUE
            ) OVER (
                PARTITION BY
                    id_agent
                ORDER BY
                    ts_status_started
            ),
            FALSE
        ) AS is_agent_for_sale,
        COALESCE(
            LAST(
                FIRST(is_agent_for_rent, TRUE),
                TRUE
            ) OVER(
                PARTITION BY
                    id_agent
                ORDER BY
                    ts_status_started
            ),
            FALSE
        ) AS is_agent_for_rent,
        COALESCE(FIRST(has_changed_activated, TRUE), FALSE) AS has_changed_activated,
        COALESCE(FIRST(has_changed_work_contract, TRUE), FALSE) AS has_changed_work_contract,
        COALESCE(FIRST(has_changed_business_context, TRUE), FALSE) AS has_changed_business_context,
        ts_status_started,
        LEAD(ts_status_started) OVER (
            PARTITION BY
                id_agent
            ORDER BY
                ts_status_started
        ) AS ts_status_ended
    FROM
        all_changes
    GROUP BY
        id_agent, ts_status_started
),
having_last_changes AS (
    SELECT
        id_agent,
        CASE
            WHEN id_work_contract = 6 -- This contract is "Agenda Bloqueada", which represents a suspension. But we still consider the contract as the previous one.
                THEN LAST(NULLIF(id_work_contract, 6), TRUE) OVER(PARTITION BY id_agent ORDER BY ts_status_started)
            ELSE id_work_contract
        END AS id_work_contract,
        COALESCE(ascc_action, bcc_action) AS action,
        is_agent_active,
        COALESCE(id_work_contract IN (6, 450, 550, 813), FALSE) AS has_blocked_schedule,
        is_agent_for_sale,
        is_agent_for_rent,
        ROUND(
            TIMESTAMPDIFF(HOUR, ts_status_started, COALESCE(ts_status_ended, NOW()))/24
        , 2) AS days_in_status,
        LAST(
            CASE
                WHEN has_changed_work_contract
                AND id_work_contract != 6
                AND id_previous_work_contract != 6
                    THEN ts_status_started 
            END, TRUE
        ) OVER (
            PARTITION BY id_agent ORDER BY ts_status_started
        ) AS ts_last_contract_changed,
        LAST(
            CASE
                WHEN has_changed_work_contract
                AND id_work_contract IN (6, 450, 550, 813)
                OR id_previous_work_contract IN (6, 450, 550, 813)
                    THEN ts_status_started 
            END, TRUE
        ) OVER (
            PARTITION BY id_agent ORDER BY ts_status_started
        ) AS ts_last_suspension_changed,
        LAST(
            CASE WHEN has_changed_activated THEN ts_status_started END, TRUE
        ) OVER (
            PARTITION BY id_agent ORDER BY ts_status_started
        ) AS ts_last_activation_changed,
        LAST(
            CASE WHEN has_changed_business_context THEN ts_status_started END, TRUE
        ) OVER(
            PARTITION BY id_agent ORDER BY ts_status_started
        ) AS ts_last_business_context_changed,
        ts_status_started,
        ts_status_ended
    FROM
        unite_simultaneous_changes
)
SELECT
    hlc.id_agent,
    wc.id AS id_work_contract,
    wc.id_company_hubspot,
    wc.3p_partner,
    hlc.action,
    hlc.days_in_status,
    hlc.is_agent_active,
    hlc.has_blocked_schedule,
    hlc.is_agent_for_sale,
    hlc.is_agent_for_rent,
    hlc.ts_last_contract_changed,
    hlc.ts_last_suspension_changed,
    hlc.ts_last_activation_changed,
    hlc.ts_last_business_context_changed,
    hlc.ts_status_started,
    hlc.ts_status_ended
FROM
    having_last_changes AS hlc
LEFT JOIN
    datalake_ebdb_work_contract.work_contract AS wc
        ON wc.id = hlc.id_work_contract
WHERE
    hlc.ts_status_started IS NOT NULL