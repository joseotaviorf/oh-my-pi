WITH all_changes AS (
    SELECT
        id_agent,
        COALESCE(id_work_contract, -1) AS id_work_contract,
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
        id_work_contract,
        COALESCE(ascc_action, bcc_action) AS action,
        is_agent_active,
        is_agent_for_sale,
        is_agent_for_rent,
        (UNIX_TIMESTAMP(COALESCE(ts_status_ended, NOW())) - UNIX_TIMESTAMP(ts_status_started))/(24 * 60 * 60) AS days_in_status,
        LAST(
            CASE WHEN has_changed_work_contract THEN ts_status_started END, TRUE
        ) OVER (
            PARTITION BY id_agent ORDER BY ts_status_started
        ) AS ts_last_contract_changed,
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
    hlc.id_agent AS sk_agent,
    COALESCE(
        dwc.sk_work_contract,
        BIGINT(-1 || INT(hlc.is_agent_active) || INT(hlc.is_agent_for_sale) || INT(hlc.is_agent_for_rent))
    ) AS sk_work_contract,
    COALESCE(cs.sk_company, -1) AS sk_company,
    COALESCE(BIGINT(DATE_FORMAT(hlc.ts_last_contract_changed, 'yyyyMMdd')), -1) AS sk_last_contract_changed_date,
    COALESCE(BIGINT(DATE_FORMAT(hlc.ts_last_activation_changed, 'yyyyMMdd')), -1) AS sk_last_activation_changed_date,
    COALESCE(BIGINT(DATE_FORMAT(hlc.ts_last_business_context_changed, 'yyyyMMdd')), -1) AS sk_last_business_context_changed_date,
    COALESCE(BIGINT(DATE_FORMAT(hlc.ts_status_started, 'yyyyMMdd')), -1) AS sk_status_started_date,
    COALESCE(BIGINT(DATE_FORMAT(hlc.ts_status_ended, 'yyyyMMdd')), -1) AS sk_status_ended_date,
    action,
    days_in_status,
    ts_last_contract_changed,
    ts_last_activation_changed,
    ts_last_business_context_changed,
    hlc.ts_status_started,
    hlc.ts_status_ended,
    NOW() AS ts_load
FROM
    having_last_changes AS hlc
LEFT JOIN
    datalake_ebdb_work_contract.work_contract AS wc
        ON wc.id = hlc.id_work_contract
LEFT JOIN
    dw_agent.dim_work_contract AS dwc
        ON dwc.id_work_contract IS NOT DISTINCT FROM NULLIF(hlc.id_work_contract, -1)
        AND dwc.is_active = hlc.is_agent_active
        AND dwc.is_for_sale_contract = hlc.is_agent_for_sale
        AND dwc.is_for_rent_contract = hlc.is_agent_for_rent
LEFT JOIN
    datalake_company.company_sks AS cs
        ON (wc.id_company_hubspot IS NOT NULL
        AND wc.id_company_hubspot = cs.id_hubspot)
        OR (wc.id_company_hubspot IS NULL
        AND wc.3p_partner = cs.extracted_3p_tag)
WHERE hlc.ts_status_started IS NOT NULL -- added clause on rotation to fix NULL values