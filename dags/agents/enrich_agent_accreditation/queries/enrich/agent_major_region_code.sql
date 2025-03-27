WITH agent_region AS (
    SELECT
        aud.id_agent_data AS id_agent,
        aud.id_region,
        r.region_code,
        aud.rev_type,
        u.ts_revision,
        COALESCE(
            LEAD(u.ts_revision) OVER (PARTITION BY aud.id_agent_data ORDER BY u.ts_revision),
            DATE('{load_end_date}')
        ) AS ts_revision_end,
        LAST(u.ts_revision) OVER (PARTITION BY aud.id_agent_data ORDER BY u.ts_revision ASC) AS ts_last_revision
    FROM
        datalake_ebdb_clean.agent_region_data_aud AS aud
    JOIN 
        datalake_ebdb_user.user_revision_entity AS u 
            ON u.id = aud.rev
    JOIN 
        datalake_region.region AS r
            ON r.id = aud.id_region
    WHERE
        TRIM(r.region_code) <> ''
        AND DATE(u.ts_revision) <= DATE('{load_end_date}')
),
total_micro_regions AS (
    SELECT
        ar.id_agent,
        ar.region_code,
        COUNT(DISTINCT ar.id_region) AS total_region_count,
        DATEDIFF(ar.ts_revision_end, ar.ts_revision) AS total_active_days,
        MIN(ar.ts_revision) AS ts_earliest_revision,
        ar.ts_revision,
        ar.ts_revision_end,
        ar.ts_last_revision
    FROM 
        agent_region AS ar
    WHERE 
        ar.rev_type <> 2
    GROUP BY ALL
),
final_regions AS (
    SELECT
        tmr.id_agent,
        tmr.region_code AS major_region_code,
        tmr.total_active_days,
        tmr.ts_revision,
        tmr.ts_revision_end
    FROM 
        total_micro_regions AS tmr
    WHERE 
        tmr.total_active_days > 0 
        OR tmr.ts_revision = tmr.ts_last_revision
    QUALIFY
        1 = ROW_NUMBER() OVER (
            PARTITION BY tmr.id_agent, tmr.ts_revision
            ORDER BY tmr.total_region_count DESC, tmr.ts_earliest_revision ASC, tmr.total_active_days DESC
        )
),
revision_ended AS (
    SELECT
        XXHASH64(fr.id_agent, fr.ts_revision) AS id_major_region_code,
        fr.id_agent,
        fr.major_region_code,
        fr.ts_revision AS ts_started,
        LEAD(fr.ts_revision) OVER (PARTITION BY fr.id_agent ORDER BY fr.ts_revision) - INTERVAL 1 DAY AS ts_ended,
        COALESCE(
            LEAD(fr.ts_revision) OVER (PARTITION BY fr.id_agent ORDER BY fr.ts_revision), 
            DATE('{load_end_date}')
        ) AS ts_updated
    FROM
        final_regions AS fr
)
SELECT
    re.id_major_region_code,
    re.id_agent,
    re.major_region_code,
    DATEDIFF(COALESCE(re.ts_ended, DATE('{load_end_date}')), re.ts_started) AS total_days_in_region_code,
    re.ts_started,
    re.ts_ended
FROM
    revision_ended AS re
WHERE
    DATE(re.ts_updated) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')