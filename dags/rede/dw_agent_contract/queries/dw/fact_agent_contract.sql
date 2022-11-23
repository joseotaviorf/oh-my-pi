WITH all_changes AS (
    SELECT
        id_agent,
        COALESCE(id_work_contract, -1) AS id_work_contract,
        action AS ascc_action,
        NULL AS bcc_action,
        is_agent_active,
        NULL AS is_agent_for_sale,
        NULL AS is_agent_for_rent,
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
)
SELECT
    usc.id_agent AS sk_agent,
    COALESCE(
        dwc.sk_work_contract,
        BIGINT(-1 || INT(usc.is_agent_active) || INT(usc.is_agent_for_sale) || INT(usc.is_agent_for_rent))
    ) AS sk_work_contract,
    COALESCE(cs.sk_company, -1) AS sk_company,
    COALESCE(BIGINT(DATE_FORMAT(usc.ts_status_started, 'yyyyMMdd')), -1) AS sk_status_started_date,
    COALESCE(BIGINT(DATE_FORMAT(usc.ts_status_ended, 'yyyyMMdd')), -1) AS sk_status_ended_date,
    COALESCE(usc.ascc_action, usc.bcc_action) AS action,
    (UNIX_TIMESTAMP(ts_status_ended) - UNIX_TIMESTAMP(ts_status_started))/(24 * 60 * 60) AS days_in_status,
    usc.ts_status_started,
    usc.ts_status_ended,
    NOW() AS ts_load
FROM
    unite_simultaneous_changes AS usc
LEFT JOIN
    datalake_ebdb_work_contract.work_contract AS wc
        ON wc.id = usc.id_work_contract
LEFT JOIN
    dw_agent.dim_work_contract AS dwc
        ON dwc.id_work_contract IS NOT DISTINCT FROM NULLIF(usc.id_work_contract, -1)
        AND dwc.is_active = usc.is_agent_active
        AND dwc.is_for_sale_contract = usc.is_agent_for_sale
        AND dwc.is_for_rent_contract = usc.is_agent_for_rent
LEFT JOIN
    datalake_rede_company.company_sks AS cs
        ON (wc.id_company_hubspot IS NOT NULL
        AND wc.id_company_hubspot = cs.id_hubspot)
        OR (wc.id_company_hubspot IS NULL
        AND wc.3p_partner = cs.extracted_3p_tag)