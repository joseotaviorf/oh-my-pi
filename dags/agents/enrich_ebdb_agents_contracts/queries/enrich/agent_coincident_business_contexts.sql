WITH business_context_changes_aux AS (
    SELECT
        id_agent AS id_agent_data,
        CASE
            WHEN business_context = 'SALE' THEN TRUE
            ELSE NULL
        END AS is_agent_for_sale,
        CASE
            WHEN business_context = 'RENT' THEN TRUE
            ELSE NULL
        END AS is_agent_for_rent,
        ts_revision_started AS ts_business_context_changed
    FROM
        datalake_agent_accreditation.business_context
    UNION ALL
    SELECT
        id_agent AS id_agent_data,
        CASE
            WHEN business_context = 'SALE' THEN FALSE
            ELSE NULL
        END AS is_agent_for_sale,
        CASE
            WHEN business_context = 'RENT' THEN FALSE
            ELSE NULL
        END AS is_agent_for_rent,
        ts_revision_ended AS ts_business_context_changed
    FROM
        datalake_agent_accreditation.business_context
    WHERE
        ts_revision_ended IS NOT NULL
)
SELECT
    id_agent_data,
    COALESCE(
        LAST( -- If there was not any non-null result in the group by, replicate the value from the previous line
            FIRST(is_agent_for_sale, TRUE), -- Gets the non-null result in the group by (if it exists)
            TRUE 
        ) OVER(
            PARTITION BY 
                id_agent_data
            ORDER BY
                ts_business_context_changed
        ), 
        FALSE
    ) AS is_agent_for_sale,
    COALESCE(
        LAST(
            FIRST(is_agent_for_rent, TRUE),
            TRUE
        ) OVER(
            PARTITION BY
                id_agent_data
            ORDER BY ts_business_context_changed
        ),
        FALSE
    ) AS is_agent_for_rent,
    TIMESTAMP(ts_business_context_changed) AS ts_agent_business_context_started,
    TIMESTAMP(
        LEAD(ts_business_context_changed) OVER (
            PARTITION BY
                id_agent_data
            ORDER BY
                ts_business_context_changed
        )
    ) AS ts_agent_business_context_ended
FROM
    business_context_changes_aux
GROUP BY
    id_agent_data, ts_business_context_changed
