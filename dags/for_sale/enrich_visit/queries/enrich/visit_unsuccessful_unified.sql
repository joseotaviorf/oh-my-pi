WITH
visit_show AS (
    SELECT
        id_booking,
        type,
        has_attended
    FROM
        datalake_ebdb_clean.visitor
    QUALIFY
        ROW_NUMBER() OVER(PARTITION BY id_booking, type ORDER BY ts_created DESC) = 1
)
SELECT
    b.id_visit,
    b.id AS id_schedule,
    b.visit_fup AS reason,
    b.visit_fup_comment AS comment,
    show_demand.has_attended AS has_demand_attended,
    show_agent.has_attended AS has_agent_attended,
    show_tenant_living.has_attended AS has_tenant_living_attended,
    show_supply.has_attended AS has_supply_attended,
    b.ts_visit_fup AS ts_visit_unsuccessful
FROM
    datalake_ebdb_clean.booking b
LEFT JOIN
    visit_show AS show_demand
        ON show_demand.id_booking = b.id
        AND show_demand.type = 'Tenant'
LEFT JOIN
    visit_show AS show_agent
        ON show_agent.id_booking = b.id
        AND show_agent.type = 'Agent'
LEFT JOIN
    visit_show AS show_tenant_living
        ON show_tenant_living.id_booking = b.id
        AND show_tenant_living.type = 'TenantLiving'
LEFT JOIN
    visit_show AS show_supply
        ON show_supply.id_booking = b.id
        AND show_supply.type = 'Landlord'
WHERE
    b.visit_fup IN ('EntradaNaoAutorizada', 'NaoCompareceu')
    AND b.type = 'Visita'
QUALIFY
    ROW_NUMBER() OVER(PARTITION BY b.id_visit ORDER BY b.id DESC) = 1
