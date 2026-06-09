WITH secretariat_allocation AS (
    SELECT
        u.id_main_user AS id_secretariat_user,
        u_parent.id_main_user AS id_supervisor_user,
        mp.id_business_unit,
        mp.profile,
        u.name AS secretariat_name,
        u.email AS secretariat_email,
        u_parent.name AS supervisor_name,
        u_parent.email AS supervisor_email,
        bu.hub_name AS allocation,
        bu.business_context,
        mp.ts_relationship_started AS ts_allocation_started,
        mp.ts_relationship_ended AS ts_allocation_ended
    FROM
        datalake_hub_services.member_profile AS mp
    LEFT JOIN 
        datalake_hub_services.users AS u
            ON u.id_user = mp.id_user
    LEFT JOIN 
        datalake_hub_services.users AS u_parent
            ON u_parent.id_user = mp.id_parent_user
    LEFT JOIN
        datalake_hub_services_clean.business_unit AS bu
            ON mp.id_business_unit = bu.id
    WHERE
        mp.profile LIKE '%SECRETARIAT%'
),
/*
On January 24th 2024, there was a major fix in Hub Services for secretariats.
Before this date, it was very common for secretariats to be associated with more than one hub, instead of being associated with a single team.
Because of that, we're going to set every allocation before this date to "Unknown", and keep everything every this date.
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
        NULL AS id_supervisor_user,
        NULL AS id_business_unit,
        sa.secretariat_name,
        sa.secretariat_email,
        NULL AS supervisor_name,
        NULL AS supervisor_email,
        'Unknown' AS allocation,
        'Unknown' AS profile,
        business_context,
        MIN(sa.ts_allocation_started) AS ts_allocation_started,
        LEAST(MAX(sa.ts_allocation_ended), '2024-01-24'::TIMESTAMP) AS ts_allocation_ended
    FROM
        secretariat_allocation AS sa
    WHERE
        sa.ts_allocation_started < '2024-01-24'
    GROUP BY ALL
)
SELECT
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
    profile,
    foh.business_context,
    ROW_NUMBER() OVER(PARTITION BY foh.id_secretariat_user ORDER BY foh.ts_allocation_started) AS version,
    foh.ts_allocation_started,
    foh.ts_allocation_ended
FROM
    filtered_out_history AS foh
