WITH listing_scheduling AS (
    SELECT
        flrf.sk_house_listing,
        db.id_agent,
        MIN(db.dt_scheduling) OVER(PARTITION BY flrf.sk_house_listing) AS ts_first_scheduling,
        MIN(db.dt_scheduling) OVER(PARTITION BY flrf.sk_house_listing, flrf.sk_user_agent) AS ts_agent_scheduled
    FROM
        dw_public.fact_listing_rent_flows AS flrf
    JOIN
        dw_public.dim_booking AS db
            ON flrf.sk_booking = db.sk_booking
    JOIN
        dw_public.dim_user AS du
            ON flrf.sk_user_agent = du.sk_user
    WHERE
        flrf.flg_visit_completed=TRUE
),
unique_listing_scheduling AS (
    SELECT
        sk_house_listing,
        id_agent,
        ts_first_scheduling,
        ts_agent_scheduled
    FROM
        listing_scheduling
    GROUP BY 1, 2, 3, 4
)
SELECT
    awk.id_house_listing AS sk_house_listing,
    COALESCE(awk.id_agent, -1) AS sk_agent,
    awk.id_house AS sk_house,
    awk.all_id_agents, 
    IF(awk.has_keys_with_agent_attributed, CAST((TO_UNIX_TIMESTAMP(uls.ts_first_scheduling) -  TO_UNIX_TIMESTAMP(awk.ts_attributed))/86400 AS DECIMAL(7,2)), NULL) AS days_attribution_to_first_vc,
    IF(awk.has_keys_with_agent_attributed, CAST((TO_UNIX_TIMESTAMP(uls.ts_agent_scheduled) - TO_UNIX_TIMESTAMP(awk.ts_attributed))/86400 AS DECIMAL(7,2)), NULL) AS days_attribution_to_first_vc_agent,
    awk.days_cs_to_return,
    awk.days_publication_to_attribution,
    awk.has_keys_with_agent_attributed,
    awk.has_keys_with_agent_delivered,
    awk.has_keys_with_agent_returned,
    CASE
        WHEN uls.ts_first_scheduling IS NOT NULL THEN 
            CASE
                WHEN DATEDIFF(awk.ts_delivered, uls.ts_agent_scheduled) < 0 THEN True
                ELSE False
            END
    END AS is_delivered_earlier_first_vc_agent,
    CASE
        WHEN uls.ts_first_scheduling IS NOT NULL THEN 
            CASE
                WHEN DATEDIFF(awk.ts_delivered, uls.ts_first_scheduling) <= 3 THEN True
                ELSE False
        END
    END AS is_delivered_first_vc,
    CASE
        WHEN uls.ts_first_scheduling IS NOT NULL THEN 
            CASE
                WHEN DATEDIFF(awk.ts_delivered, uls.ts_agent_scheduled) <= 3 THEN True
                ELSE False
            END
    END AS is_delivered_first_vc_agent,
    awk.is_delivered_on_another_listing,
    awk.is_keys_with_agent_eligible,
    awk.is_keys_with_agent_opt_in,
    awk.is_fss,
    awk.is_returned_on_time,
    CAST(awk.ts_attributed AS TIMESTAMP) AS ts_attributed,
    CAST(awk.ts_contract_signed AS TIMESTAMP) AS ts_contract_signed,
    CAST(awk.ts_delivered AS TIMESTAMP) AS ts_delivered,
    CAST(uls.ts_first_scheduling AS TIMESTAMP) AS ts_first_vc,
    CAST(uls.ts_agent_scheduled AS TIMESTAMP) AS ts_first_vc_attributed,
    CAST(awk.ts_optin AS TIMESTAMP) AS ts_optin,
    CAST(awk.ts_publicated AS TIMESTAMP) AS ts_publicated,
    CAST(awk.ts_returned AS TIMESTAMP) AS ts_returned,
    NOW() AS ts_load
FROM
    datalake_ebdb_listing.agents_with_keys AS awk
LEFT JOIN
    unique_listing_scheduling AS uls
        ON awk.id_house_listing = uls.sk_house_listing
        AND awk.id_agent = uls.id_agent