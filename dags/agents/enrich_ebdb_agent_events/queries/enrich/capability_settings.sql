WITH capability_settings_updated AS (
    SELECT
        settings.id
    FROM
        datalake_ebdb_clean.demand_visit_management_capability_settings AS settings
    WHERE
        DATE(settings.ts_updated) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
),
-- CDC can emit CREATE and UPDATE rows with the same (id, updated_at), which collide on
-- XXHASH64(id, updated_at) and invert LEAD() windows. Keep one revision per instant.
settings_revisions_ranked AS (
    SELECT
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
        settings.created_at AS ts_created,
        settings.updated_at AS ts_started,
        settings.year,
        settings.month,
        settings.day,
        ROW_NUMBER() OVER (
            PARTITION BY
                settings.id,
                settings.updated_at
            ORDER BY
                CASE settings.op_cdc
                    WHEN 'u' THEN 0
                    WHEN 'c' THEN 1
                    WHEN 'd' THEN 2
                    ELSE 3
                END
        ) AS revision_rank
    FROM
        capability_settings_updated AS updated
    JOIN
        datalake_ebdb_transactional.DemandVisitManagementCapabilitySettings AS settings
            ON updated.id = settings.id
    JOIN
        datalake_ebdb_clean.capability AS cap
            ON settings.capability_id = cap.id
),
settings_revisions AS (
    SELECT
        id_agent,
        id_capability,
        id_capability_settings,
        rev_type,
        business_context,
        is_passive_lead_receiver,
        ts_created,
        ts_started,
        year,
        month,
        day
    FROM
        settings_revisions_ranked
    WHERE
        revision_rank = 1
)
SELECT
    XXHASH64(settings.id_capability_settings, settings.ts_started) AS id_event_log,
    settings.id_agent,
    settings.id_capability,
    settings.id_capability_settings,
    settings.rev_type,
    settings.business_context,
    settings.is_passive_lead_receiver,
    FIRST_VALUE(settings.ts_started) OVER(PARTITION BY settings.id_capability_settings ORDER BY settings.ts_started DESC) = settings.ts_started AS is_current_status,
    ROW_NUMBER() OVER(PARTITION BY settings.id_capability_settings, DATE(settings.ts_started) ORDER BY settings.ts_started DESC) = 1 AS is_last_update_by_date,
    settings.ts_created,
    settings.ts_started,
    LEAD(settings.ts_started) OVER (PARTITION BY settings.id_capability_settings ORDER BY settings.ts_started) AS ts_ended,
    settings.year,
    settings.month,
    settings.day
FROM
    settings_revisions AS settings

