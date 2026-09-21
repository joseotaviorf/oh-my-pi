WITH capability_settings_updated AS (
    SELECT
        settings.id
    FROM
        datalake_ebdb_clean.demand_visit_management_capability_settings AS settings
    WHERE
        DATE(settings.ts_updated) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
)
SELECT
    XXHASH64(settings.id, settings.op_cdc, settings.updated_at, settings.ts_cdc_transaction) AS id_event_log,
    cap.id_agent,
    settings.capability_id AS id_capability,
    settings.id AS id_capability_settings,
    CASE
        WHEN settings.op_cdc = 'c' THEN "CREATE"
        WHEN settings.op_cdc = 'r' THEN "READ"
        WHEN settings.op_cdc = 'u' THEN "UPDATE"
        WHEN settings.op_cdc = 'd' THEN "DELETE"
    END AS rev_type,
    settings.business_context,
    COALESCE(settings.passive_lead_receiver, FALSE) AS is_passive_lead_receiver,
    ROW_NUMBER() OVER(
        PARTITION BY settings.id 
        ORDER BY 
            settings.updated_at DESC,
            settings.ts_cdc_transaction DESC,
            CASE WHEN settings.op_cdc = 'c' THEN 0 ELSE 1 END DESC -- CDC can emit CREATE and UPDATE rows with the same instant.
    ) = 1 AS is_current_status,
    ROW_NUMBER() OVER (
        PARTITION BY settings.id, DATE(settings.updated_at) 
        ORDER BY 
            settings.updated_at DESC,
            settings.ts_cdc_transaction DESC,
            CASE WHEN settings.op_cdc = 'c' THEN 0 ELSE 1 END DESC -- CDC can emit CREATE and UPDATE rows with the same instant.
    ) = 1 AS is_last_update_by_date,
    settings.created_at AS ts_created,
    settings.updated_at AS ts_started,
    LEAD(settings.updated_at) OVER (PARTITION BY settings.id ORDER BY settings.updated_at, settings.ts_cdc_transaction) AS ts_ended,
    settings.year,
    settings.month,
    settings.day
FROM
    capability_settings_updated AS updated
JOIN
    datalake_ebdb_transactional.DemandVisitManagementCapabilitySettings AS settings
        ON updated.id = settings.id
JOIN
    datalake_ebdb_clean.capability AS cap
        ON settings.capability_id = cap.id
