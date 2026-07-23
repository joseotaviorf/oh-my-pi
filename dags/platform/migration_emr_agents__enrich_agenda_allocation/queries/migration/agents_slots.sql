WITH active_history_mod AS (
    SELECT DISTINCT
        da.id,
        da.is_active AS is_active,
        COALESCE(lag(is_active) OVER (PARTITION BY da.id ORDER BY CAST(rev AS BIGINT))<>is_active,true) AS mod_is_active,
        ure.ts_revision
    FROM
        datalake_ebdb_clean.agent_data_aud da
    LEFT JOIN 
        datalake_ebdb_user.user_revision_entity ure
            ON da.rev = ure.id
),
active_history AS (
    SELECT
        id AS id_agent,
        is_active,
        COALESCE(lead(ts_revision) OVER (PARTITION BY id ORDER BY ts_revision), DATE('2300-01-01')) AS ts_last_version,
        ts_revision
    FROM
        active_history_mod ahm
    WHERE
        ahm.mod_is_active = true
),
specific_updates AS (
    SELECT 
        bs.id_agent,
        bs.agent_type,
        bs.day_of_week,
        CASE
            WHEN ss.is_off_work = true 
                AND ss.is_available_slot <> bs.is_available_slot THEN 'day off'
            WHEN ss.is_available_slot IS NOT NULL 
                AND ss.is_available_slot <> bs.is_available_slot THEN 'specific'
            ELSE NULL
        END AS last_change_reason,
        bs.slot_number,
        CASE
            WHEN ss.is_off_work = true 
                AND ss.is_available_slot <> bs.is_available_slot THEN false
            WHEN ss.is_available_slot IS NOT NULL 
                AND ss.is_available_slot <> bs.is_available_slot THEN ss.is_available_slot
            ELSE bs.is_available_slot
        END AS is_available_slot,
        CASE
            WHEN ss.is_off_work = true 
                AND ss.is_available_slot <> bs.is_available_slot THEN true
            WHEN ss.is_available_slot IS NOT NULL 
                AND ss.is_available_slot <> bs.is_available_slot THEN true
            ELSE false
        END AS is_specific_update,
        CASE 
            WHEN ss.is_available_slot IS NOT NULL 
                AND ss.is_available_slot <> bs.is_available_slot THEN ss.ts_updated 
            ELSE NULL 
        END AS ts_last_specific_updated,
        bs.ts_updated AS ts_last_weekly_updated,
        bs.ts_slot
    FROM
        datalake_agenda_allocation.agents_weekly_schedule_history bs
    LEFT JOIN 
        datalake_agenda_allocation.agents_specific_weekly_schedule ss
            ON bs.id_agent = ss.id_agent
            AND bs.ts_slot = ss.ts_slot
),
time_window_updates AS (
    SELECT
        sc.id_agent,
        sc.agent_type,
        sc.day_of_week,
        CASE
            WHEN is_available_slot = true
                AND (UNIX_TIMESTAMP(ts_slot) - UNIX_TIMESTAMP(COALESCE(ts_last_specific_updated, ts_last_weekly_updated)))/3600 < 96 THEN '96 hours'
            ELSE sc.last_change_reason
        END AS last_change_reason,
        sc.slot_number,
        CASE
            WHEN is_available_slot = true
                AND (UNIX_TIMESTAMP(ts_slot) - UNIX_TIMESTAMP(COALESCE(ts_last_specific_updated, ts_last_weekly_updated)))/3600 < 96 THEN false
            ELSE is_available_slot
        END AS is_available_slot,
        CASE
            WHEN is_available_slot = true
                AND (UNIX_TIMESTAMP(ts_slot) - UNIX_TIMESTAMP(COALESCE(ts_last_specific_updated, ts_last_weekly_updated)))/3600 < 24 THEN false
            ELSE is_available_slot
        END AS is_available_slot_24h,
        sc.is_available_slot AS is_available_specific_slot,
        is_specific_update,
        CASE
            WHEN is_available_slot = true
                AND (UNIX_TIMESTAMP(ts_slot) - UNIX_TIMESTAMP(COALESCE(ts_last_specific_updated, ts_last_weekly_updated)))/3600 < 96 THEN true
            ELSE false
        END AS is_time_window_update,
        sc.ts_last_weekly_updated,
        sc.ts_last_specific_updated,
        sc.ts_slot
    FROM
        specific_updates sc
)
SELECT
    tw.id_agent,
    tw.agent_type,
    tw.day_of_week,
    tw.last_change_reason,
    tw.slot_number,
    CAST(ah.is_active AS BOOLEAN) AS is_active,
    CAST(tw.is_available_slot AS BOOLEAN) AS is_available_slot,
    CAST(tw.is_available_slot_24h AS BOOLEAN) AS is_available_slot_24h,
    CAST(tw.is_available_specific_slot AS BOOLEAN) AS is_available_specific_slot,
    CAST(tw.is_specific_update AS BOOLEAN) AS is_specif_update, 
    CAST(tw.is_time_window_update AS BOOLEAN) AS is_time_window_update,
    CAST(tw.ts_last_specific_updated AS TIMESTAMP) AS ts_last_specific_updated,
    CAST(tw.ts_last_weekly_updated AS TIMESTAMP) AS ts_last_weekly_updated,
    CAST(tw.ts_slot AS TIMESTAMP) AS ts_slot,
    YEAR(ts_slot) AS year,
    MONTH(ts_slot) AS month, 
    DAY(ts_slot) AS day
FROM
    time_window_updates tw
LEFT JOIN  
    active_history ah
        ON ah.id_agent = tw.id_agent
        AND tw.ts_slot BETWEEN ah.ts_revision
        AND ah.ts_last_version
WHERE
    DATE(tw.ts_slot) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}') + INTERVAL 21 DAYS
    AND ah.is_active = true