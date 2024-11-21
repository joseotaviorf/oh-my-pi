WITH member_profile AS (
    SELECT
        mp.id,
        mp.id_business_unit,
        mp.id_user,
        mp.profile,
        mp.is_active,
        ts_created AS ts_allocation_started,
        LEAD(mp.ts_created) OVER(PARTITION BY mp.id ORDER BY mp.ts_created) AS ts_allocation_ended
    FROM
        datalake_hub_services_clean.member_profile_aud AS mp
    WHERE
        (mp.mod_id_business_unit OR mp.mod_active)
        AND mp.profile LIKE '%SECRETARIAT%'
    QUALIFY
        is_active
),
secretariat_allocation AS (
    SELECT
        secretariat_info.id_external AS id_secretariat_user,
        bu.id AS id_business_unit,
        bu.hub_name AS allocation,
        bu.business_context,
        ur_ag.profile,
        ur_ag.ts_allocation_started,
        ur_ag.ts_allocation_ended
    FROM
        member_profile AS ur_ag
    LEFT JOIN
        datalake_hub_services_clean.business_unit AS bu
            ON ur_ag.id_business_unit = bu.id
    LEFT JOIN
        datalake_hub_services_clean.users AS secretariat_info
            ON ur_ag.id_user = secretariat_info.id
    LEFT JOIN
        datalake_hub_services_clean.member_profile AS mp
            ON mp.id = ur_ag.id
),
first_allocation_by_user_in_hub_services AS (
    SELECT
        id_secretariat_user,
        MIN(ts_allocation_started) AS ts_first_allocation
    FROM
        secretariat_allocation
    GROUP BY 1
),
legacy_secretariat AS (
    SELECT
        id_user_5a AS id_secretariat_user,
        NULL::BIGINT AS id_business_unit,
        allocation,
        'SALE' AS business_context,
        NULL::STRING AS profile,
        dt_started AS ts_allocation_started,
        LEAST(
            LEAD(sh.dt_started) OVER(PARTITION BY sh.id_user_5a ORDER BY sh.dt_started),
            fa.ts_first_allocation
        ) AS ts_allocation_ended
    FROM
        datalake_gsheets_clean.secretariat_hierarchy AS sh
    LEFT JOIN
        first_allocation_by_user_in_hub_services AS fa
            ON sh.id_user_5a = fa.id_secretariat_user
    WHERE
        sh.dt_started < fa.ts_first_allocation
),
united_allocations AS (
    SELECT *
    FROM
        legacy_secretariat
    UNION ALL
    SELECT *
    FROM
        secretariat_allocation
),
/*
On January 24th 2024, there was a major fix in Hub Services for secretariats.
Before this date, it was very common for secretariats to be associated with more than one hub, instead of being associated with a single team.
Because of that, we're going to set every allocation before this date to "Unknown", and keep everything every this date.
*/
filtered_out_history AS (
    SELECT
        sa.id_secretariat_user,
        sa.id_business_unit,
        sa.allocation,
        sa.profile,
        sa.business_context,
        GREATEST(sa.ts_allocation_started, '2024-01-24'::TIMESTAMP) AS ts_allocation_started,
        sa.ts_allocation_ended
    FROM
        secretariat_allocation AS sa
    WHERE
        sa.ts_allocation_ended IS NULL
        OR sa.ts_allocation_ended >= '2024-01-24'
    UNION ALL
    SELECT
        sa.id_secretariat_user,
        NULL AS id_business_unit,
        'Unknown' AS allocation,
        'Unknown' AS profile,
        business_context,
        MIN(sa.ts_allocation_started) AS ts_allocation_started,
        LEAST(MAX(sa.ts_allocation_ended), '2024-01-24'::TIMESTAMP) AS ts_allocation_ended
    FROM
        secretariat_allocation AS sa
    WHERE
        sa.ts_allocation_started < '2024-01-24'
    GROUP BY
        sa.id_secretariat_user,
        sa.business_context
)
SELECT
    id_secretariat_user,
    id_business_unit,
    allocation,
    CASE
        WHEN allocation = 'Unknown' THEN 'Unknown'
        WHEN allocation LIKE '%HUB%' THEN 'HUB'
        WHEN allocation LIKE '%Growth%' THEN 'Growth'
        WHEN allocation LIKE '%3P%' THEN '3P'
        WHEN allocation LIKE '%CENTRAL%' THEN 'Central'
        WHEN allocation LIKE '%Lite%' THEN 'NBP'
        WHEN allocation LIKE '%BWA%' THEN 'BWA'
        ELSE 'Other'
    END AS segment,
    profile,
    business_context,
    ROW_NUMBER() OVER(PARTITION BY id_secretariat_user ORDER BY ts_allocation_started) AS version,
    ts_allocation_started,
    ts_allocation_ended
FROM
    filtered_out_history
