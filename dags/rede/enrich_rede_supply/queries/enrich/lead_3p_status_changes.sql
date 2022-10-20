WITH first_time_for_status AS (
    SELECT *
    FROM (
        SELECT
            id_lead_3p,
            status,
            CASE
                WHEN status != 'NOT_CONVERTED' THEN FALSE
                ELSE has_owner_info
            END AS is_not_converted_with_owner_info,
            ts_status_started
        FROM
            datalake_rede_supply.simplified_lead_3p_status_changes
    )
    PIVOT (
        MIN(ts_status_started)
        FOR (status, is_not_converted_with_owner_info) IN (
            ('NOT_CONVERTED', FALSE) AS ts_first_not_converted_wo_owner,
            ('WAITING', FALSE) AS ts_first_waiting,
            ('NOT_CONVERTED', TRUE) AS ts_first_not_converted_w_owner,
            ('PROCESSING', FALSE) AS ts_first_processing,
            ('REGISTERED', FALSE) AS ts_first_registered
        )
    )
),
status_changes AS (
    SELECT
        sc.id_status_change,
        sc.id_lead_3p,
        sc.id_company_hubspot,
        sc.id_file,
         CASE
            WHEN sc.status = 'REGISTERED' THEN FIRST(id_house, TRUE) OVER (PARTITION BY sc.id_lead_3p ORDER BY sc.ts_status_started)
            ELSE id_house 
        END AS id_house,
        sc.status,
        sc.listing_status,
        CASE
            WHEN sc.listing_status IS NOT NULL OR sc.ts_status_started >= ts_first_registered THEN 'FIRST_LISTING'
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
),
status_ended_aux AS (
    SELECT
        id_status_change,
        id_lead_3p,
        id_company_hubspot,
        LAST(id_file, TRUE) OVER (PARTITION BY id_lead_3p ORDER BY ts_status_started) AS id_file,
        LAST(id_house, TRUE) OVER (PARTITION BY id_lead_3p ORDER BY ts_status_started) AS id_house,
        COALESCE(status, listing_status) AS status,
        growth_status,
        is_waiting_for_enrichment,
        is_ineligible,
        is_discarded,
        ts_status_started,
        LEAD(ts_status_started) OVER (PARTITION BY id_lead_3p ORDER BY ts_status_started) AS ts_status_ended
    FROM
        status_changes
    WHERE
        listing_status IS NULL
        OR listing_status IN ('PUBLISHED', 'UNPUBLISHED')
)
SELECT
    id_status_change,
    id_lead_3p,
    id_company_hubspot,
    id_file,
    id_house,
    status,
    growth_status,
    DATEDIFF(ts_status_ended, ts_status_started) AS days_in_status,
    is_waiting_for_enrichment,
    is_ineligible,
    is_discarded,
    ts_status_started,
    ts_status_ended
FROM
    status_ended_aux