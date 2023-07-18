WITH first_time_for_status AS (
    SELECT *
    FROM (
        SELECT
            id_lead_3p,
            business_context,
            COALESCE(
                status, 
                CASE
                    WHEN listing_status IN ('PUBLISHED', 'UNPUBLISHED') THEN listing_status
                END
            ) AS compressed_status,
            CASE
                WHEN status IS DISTINCT FROM 'NOT_CONVERTED' THEN FALSE
                ELSE has_owner_info
            END AS is_not_converted_with_owner_info,
            ts_status_started
        FROM
            datalake_rede_supply.simplified_lead_3p_status_changes
    )
    PIVOT (
        MIN(ts_status_started)
        FOR (
            compressed_status, is_not_converted_with_owner_info
        ) IN (
            ('NOT_CONVERTED', FALSE) AS ts_first_not_converted_wo_owner,
            ('WAITING', FALSE) AS ts_first_waiting,
            ('NOT_CONVERTED', TRUE) AS ts_first_not_converted_w_owner,
            ('PROCESSING', FALSE) AS ts_first_processing,
            ('PUBLISHED', FALSE) AS ts_first_published
        )
    )
),
status_changes AS (
    SELECT
        sc.id_status_change,
        sc.id_lead_3p,
        sc.id_file,
         CASE
            WHEN sc.status = 'REGISTERED' THEN FIRST(id_house, TRUE) OVER (PARTITION BY sc.id_lead_3p, sc.business_context ORDER BY sc.ts_status_started)
            ELSE id_house 
        END AS id_house,
        sc.business_context,
        sc.status,
        sc.listing_status,
        CASE
            WHEN sc.ts_status_started >= ts_first_published THEN 'FIRST_LISTING'
            WHEN sc.ts_status_started >= ts_first_processing THEN 'OPPORTUNITY'
            WHEN sc.ts_status_started >= ts_first_not_converted_w_owner THEN 'QUALIFIED'
            WHEN sc.ts_status_started >= ts_first_waiting THEN 'PROSPECT'
            ELSE 'LEAD'
        END AS growth_status,
        is_waiting_for_enrichment,
        is_ineligible,
        is_discarded,
        ts_status_started
    FROM
        datalake_rede_supply.simplified_lead_3p_status_changes AS sc
    JOIN
        first_time_for_status AS ft
            ON ft.id_lead_3p = sc.id_lead_3p
            AND ft.business_context = sc.business_context
    QUALIFY
        LAG(
            COALESCE(sc.status, sc.listing_status)
        ) OVER (
            PARTITION BY sc.id_lead_3p, sc.business_context ORDER BY sc.ts_status_started
        ) IS DISTINCT FROM COALESCE(sc.status, sc.listing_status)
        OR LAG(growth_status) OVER (PARTITION BY sc.id_lead_3p, sc.business_context ORDER BY sc.ts_status_started) IS DISTINCT FROM growth_status
),
status_ended_aux AS (
    SELECT
        id_status_change,
        id_lead_3p,
        LAST(id_file, TRUE) OVER (PARTITION BY id_lead_3p, business_context ORDER BY ts_status_started) AS id_file,
        LAST(id_house, TRUE) OVER (PARTITION BY id_lead_3p, business_context ORDER BY ts_status_started) AS id_house,
        business_context,
        COALESCE(status, listing_status) AS status,
        growth_status,
        is_waiting_for_enrichment,
        is_ineligible,
        is_discarded,
        ts_status_started,
        LEAD(ts_status_started) OVER (PARTITION BY id_lead_3p, business_context ORDER BY ts_status_started) AS ts_status_ended
    FROM
        status_changes
    WHERE
        listing_status IS NULL
        OR listing_status IN ('PUBLISHED', 'UNPUBLISHED')
)
SELECT
    sea.id_status_change,
    sea.id_lead_3p,
    l.id_company_hubspot,
    l.uuid_company,
    sea.id_file,
    sea.id_house,
    sea.business_context,
    sea.status,
    sea.growth_status,
    DATEDIFF(sea.ts_status_ended, sea.ts_status_started) AS days_in_status,
    sea.is_waiting_for_enrichment,
    sea.is_ineligible,
    sea.is_discarded,
    sea.ts_status_started,
    sea.ts_status_ended
FROM
    status_ended_aux AS sea
JOIN
    datalake_brokers_supply_processor.lead_3p AS l
        ON sea.id_lead_3p = l.id
