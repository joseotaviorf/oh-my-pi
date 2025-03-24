WITH agent_region AS (
    SELECT
        aud.id_agent_data AS id_agent,
        aud.id_region,
        r.region_code,
        aud.rev_type,
        u.ts_revision,
        COALESCE(
            LEAD(u.ts_revision) OVER (PARTITION BY aud.id_agent_data, aud.id_region ORDER BY u.ts_revision),
            '{load_end_date}'
        ) AS ts_revision_end
    FROM
        datalake_ebdb_clean.agent_region_data_aud AS aud
    JOIN 
        datalake_ebdb_user.user_revision_entity AS u 
            ON u.id = aud.rev
    JOIN 
        datalake_region.region AS r
            ON r.id = aud.id_region
    WHERE
        DATE(u.ts_revision) <= DATE('{load_end_date}')
),
region_by_day AS (
    SELECT
        ad.date AS dt_reference,
        ar.id_agent,
        ar.id_region,
        ar.region_code,
        ar.rev_type,
        ar.ts_revision
    FROM
        agent_region AS ar
    JOIN
        datalake_quintoandar.aux_date AS ad
            ON ad.date BETWEEN DATE(ar.ts_revision) AND DATE(ar.ts_revision_end)
    WHERE
        ar.rev_type <> 2
        AND ad.date BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
),  
total_micro_regions AS (
    SELECT 
        ar.dt_reference,
        ar.id_agent,
        ar.region_code,
        COUNT(DISTINCT ar.id_region) AS total_micro_regions,
        MAX(ar.ts_revision) AS ts_last_update
    FROM 
        region_by_day AS ar
    GROUP BY ALL 
),
major_region_code AS (
    SELECT
        ar.dt_reference,
        ar.id_agent,
        ar.region_code AS major_region_code
    FROM
        region_by_day AS ar
    JOIN
        total_micro_regions AS tmr
            ON tmr.id_agent = ar.id_agent
            AND tmr.region_code = ar.region_code
            AND tmr.dt_reference = ar.dt_reference
    QUALIFY
        1 = ROW_NUMBER() OVER (PARTITION BY ar.dt_reference, ar.id_agent ORDER BY tmr.total_micro_regions DESC, ar.ts_revision DESC)
),
grouped_intervals AS (
    SELECT 
        ar.dt_reference,
        ar.id_agent,
        ar.major_region_code,
        SUM(
            CASE 
                WHEN 
                    LAG(ar.major_region_code) OVER (PARTITION BY ar.id_agent ORDER BY ar.dt_reference) <> ar.major_region_code 
                THEN 1 
                ELSE 0 
            END
        ) OVER (PARTITION BY ar.id_agent ORDER BY ar.dt_reference) AS id_group
    FROM 
        major_region_code AS ar
)
SELECT
    XXHASH64(gi.id_agent, gi.major_region_code, MIN(gi.dt_reference)) AS id_major_region_code,
    gi.id_agent,
    gi.major_region_code,
    DATEDIFF(MAX(gi.dt_reference), MIN(gi.dt_reference)) AS total_active_days,
    MIN(gi.dt_reference) AS dt_started,
    MAX(gi.dt_reference) AS dt_ended
FROM 
    grouped_intervals AS gi
GROUP BY 
    gi.id_agent, gi.major_region_code, gi.id_group