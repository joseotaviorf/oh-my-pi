SELECT
    id_user,
    uuid_person,
    'TENANT' AS persona,
    is_active,
    ts_first_event,
    ts_last_event,
    NOW() AS ts_load
FROM
    datalake_cdp_personas.tenant
UNION ALL
SELECT
    id_user,
    uuid_person,
    'TENANT_PROSPECT' AS persona,
    is_active,
    ts_first_event,
    ts_last_event,
    NOW() AS ts_load
FROM
    datalake_cdp_personas.tenant_prospect
UNION ALL
SELECT
    id_user,
    uuid_person,
    'BUYER_PROSPECT' AS persona,
    is_active,
    ts_first_event,
    ts_last_event,
    NOW() AS ts_load
FROM
    datalake_cdp_personas.buyer_prospect
UNION ALL
SELECT
    id_user,
    uuid_person,
    'OWNER' AS persona,
    is_active,
    ts_first_event,
    ts_last_event,
    NOW() AS ts_load
FROM
    datalake_cdp_personas.owner
UNION ALL
SELECT
    id_user,
    uuid_person,
    'PARTNER_CIQ' AS persona,
    is_active,
    ts_first_event,
    ts_last_event,
    NOW() AS ts_load
FROM
    datalake_cdp_personas.partner_ciq