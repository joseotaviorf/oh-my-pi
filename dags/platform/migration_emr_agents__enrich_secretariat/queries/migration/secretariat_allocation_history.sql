WITH secretariat_allocation AS (
    SELECT
        mp.id_main_user AS id_secretariat_user,
        mp.id_parent_main_user AS id_supervisor_user,
        mp.id_business_unit,
        mp.profile,
        mp.name AS secretariat_name,
        mp.email AS secretariat_email,
        mp.parent_name AS supervisor_name,
        mp.parent_email AS supervisor_email,
        mp.hub_name AS allocation,
        mp.business_context,
        mp_current.is_active,
        mp.ts_relationship_started AS ts_allocation_started,
        mp.ts_relationship_ended AS ts_allocation_ended
    FROM
        datalake_hub_services.member_profile AS mp
    LEFT JOIN
        datalake_hub_services_clean.member_profile AS mp_current
            ON mp_current.id = mp.id_member_profile
    WHERE
        mp.profile LIKE '%SECRETARIAT%'
),
/*
On January 24th 2024, there was a major fix in Hub Services for secretariats.
Before this date, it was very common for secretariats to be associated with more than one hub, instead of being associated with a single team.
*/
filtered_out_history AS (
    SELECT
        sa.id_secretariat_user,
        sa.id_supervisor_user,
        sa.id_business_unit,
        sa.secretariat_name,
        sa.secretariat_email,
        sa.supervisor_name,
        sa.supervisor_email,
        sa.allocation,
        sa.profile,
        sa.business_context,
        sa.is_active,
        GREATEST(sa.ts_allocation_started, TIMESTAMP('2024-01-24')) AS ts_allocation_started,
        sa.ts_allocation_ended
    FROM
        secretariat_allocation AS sa
    WHERE
        sa.ts_allocation_ended IS NULL
        OR sa.ts_allocation_ended >= '2024-01-24'
    UNION ALL
    SELECT
        COALESCE(sh.id_user_5a, sa.id_secretariat_user) AS id_secretariat_user,
        NULL AS id_supervisor_user,
        NULL AS id_business_unit,
        COALESCE(sh.secretariat_name, sa.secretariat_name) AS secretariat_name,
        COALESCE(sh.email, sa.secretariat_email) AS secretariat_email,
        NULL AS supervisor_name,
        NULL AS supervisor_email,
        COALESCE(NULLIF(sh.allocation, ''), 'Unknown') AS allocation,
        'Unknown' AS profile,
        NULL AS business_context,
        MAX(COALESCE(sa.is_active, sh.status = 'Ativo')) AS is_active,
        MIN(COALESCE(TIMESTAMP(sh.dt_started), sa.ts_allocation_started)) AS ts_allocation_started,
        LEAST(MAX(sa.ts_allocation_ended), TIMESTAMP('2024-01-24')) AS ts_allocation_ended
    FROM
        secretariat_allocation AS sa
    FULL OUTER JOIN
        datalake_gsheets_clean.secretariat_hierarchy AS sh
            ON sh.id_user_5a = sa.id_secretariat_user
    WHERE
        sa.ts_allocation_started < '2024-01-24'
        OR (
          sh.id_user_5a IS NOT NULL
          AND NULLIF(sh.allocation, '') IS NOT NULL
          AND sh.dt_started < '2024-01-24'
        )
    GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9
)
SELECT
    (
        foh.id_secretariat_user * 1000 
        + ROW_NUMBER() OVER(PARTITION BY foh.id_secretariat_user ORDER BY foh.ts_allocation_started, foh.ts_allocation_ended)
    ) AS id_secretariat_user_version,
    foh.id_secretariat_user,
    foh.id_supervisor_user,
    foh.id_business_unit,
    foh.secretariat_name,
    foh.secretariat_email,
    foh.supervisor_name,
    foh.supervisor_email,
    foh.allocation,
    CASE
        WHEN foh.allocation = "Unknown" THEN "Unknown"
        WHEN foh.allocation LIKE "%HUB%" THEN "HUB"
        WHEN foh.allocation LIKE "%Growth%" THEN "Growth"
        WHEN foh.allocation LIKE "%3P%" THEN "3P"
        WHEN foh.allocation LIKE "%CENTRAL%" THEN "Central"
        WHEN foh.allocation LIKE "%Lite%" THEN "NBP"
        WHEN foh.allocation LIKE "%BWA%" THEN "BWA"
        WHEN foh.allocation = "Secretaria ForSale - Aquisição RMSP"
            OR foh.allocation = "Secretaria ForSale - Aquisição BH"
            OR foh.allocation = "Secretaria ForSale - Aquisição RJ"
            OR foh.allocation = "Secretaria ForSale - Aquisição POA"
            THEN "Aquisição ForSale"
        WHEN foh.allocation = "Secretaria ForSale - Engajamento" THEN "Engajamento ForSale"
        WHEN foh.allocation = "Secretaria ForRent - Aquisição" THEN "Aquisição ForRent"
        WHEN foh.allocation = "Secretaria ForRent - Engajamento" THEN "Engajamento ForRent"
        WHEN foh.allocation = "Secretaria ForSale - Férias/Afastamento"
            OR foh.allocation = "Secretaria ForRent - Férias/Afastamento"
            THEN "Férias/Afastamento"
        WHEN foh.allocation = "SEC Desativado" THEN "Desativado"
        ELSE "Other"
    END AS segment,
    foh.profile,
    foh.business_context,
    ROW_NUMBER() OVER(PARTITION BY foh.id_secretariat_user ORDER BY foh.ts_allocation_started, foh.ts_allocation_ended) AS version,
    ROW_NUMBER() OVER(PARTITION BY foh.id_secretariat_user ORDER BY foh.ts_allocation_started DESC, foh.ts_allocation_ended DESC) = 1 AS is_last_version,
    foh.is_active,
    foh.ts_allocation_started,
    foh.ts_allocation_ended
FROM
    filtered_out_history AS foh
