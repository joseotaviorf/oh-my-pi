SELECT
    rde.id_tenant_prospect AS id_user,
    u.uuid_person,
    CAST(NULL AS BOOLEAN) AS is_active,
    MIN(rde.ts_event) AS ts_first_event,
    MAX(rde.ts_event) AS ts_last_event,
    NOW() AS ts_load
FROM
    datalake_rent_demand_events.rent_demand_events AS rde
LEFT JOIN
    datalake_ebdb_clean.user AS u
        ON u.id = rde.id_tenant_prospect
GROUP BY 1, 2, 3, 6