SELECT
    sde.id_buyer AS id_user,
    u.uuid_person,
    CAST(NULL AS BOOLEAN) AS is_active,
    MIN(sde.ts_event) AS ts_first_event,
    MAX(sde.ts_event) AS ts_last_event,
    NOW() AS ts_load
FROM
    datalake_sale_demand_events.sale_demand_events AS sde
LEFT JOIN
    datalake_ebdb_clean.user AS u
        ON u.id = sde.id_buyer
GROUP BY 1, 2, 3, 6