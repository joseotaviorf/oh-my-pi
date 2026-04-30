WITH visit_show AS (
    SELECT
        id_booking,
        type,
        has_attended
    FROM
        datalake_ebdb_clean.visitor
    QUALIFY
        ROW_NUMBER() OVER(PARTITION BY id_booking, type ORDER BY ts_created DESC, ts_updated DESC, id DESC) = 1
),
visit_status_log AS ( -- This is to handle the case where the visit_fup is not in the booking table (missing data from visit finalization rollout) so the visit finalization is enriched temporarily from visit_status_log table.
    SELECT
        id_visit,
        id_schedule,
        CASE
            WHEN event_type = 'VISIT_DONE' THEN 'VaiNegociar'
            WHEN event_type = 'VISIT_UNSUCCESSFUL' AND reason IN ('DEMAND_DID_NOT_ATTEND_VISIT', 'AGENT_DID_NOT_ATTEND_VISIT', 'SUPPLY_DID_NOT_ATTEND_VISIT') THEN 'NaoCompareceu'
            WHEN event_type = 'VISIT_UNSUCCESSFUL' AND reason IN ('ACCESS_TO_HOUSE_NOT_AUTHORIZED', 'HOUSE_KEYS_NOT_AVAILABLE', 'HOUSE_NO_LONGER_AVAILABLE_FOR_RENT', 'TENANT_LIVING_DID_NOT_ALLOW_VISIT', 'HOUSE_NO_LONGER_AVAILABLE_FOR_SALE') THEN 'EntradaNaoAutorizada'
        END AS visit_fup,
        ts_created AS ts_visit_fup
    FROM
        datalake_visit.visit_status_events
    WHERE
        ts_created::DATE >= '2025-01-01'
        AND event_type IN ('VISIT_DONE', 'VISIT_UNSUCCESSFUL')
    QUALIFY
        ROW_NUMBER() OVER(PARTITION BY id_visit ORDER BY id_visit_status_log DESC) = 1
)
SELECT
    b.id_visit,
    b.id AS id_schedule,
    COALESCE(b.visit_fup, vsl.visit_fup) AS reason,
    CASE
        WHEN COALESCE(b.visit_fup, vsl.visit_fup) IN ('VaiNegociar', 'NaoGostou', 'VisitouSozinho', 'Talvez') THEN 'VISIT_DONE'
        WHEN COALESCE(b.visit_fup, vsl.visit_fup) IN ('EntradaNaoAutorizada', 'NaoCompareceu', 'ImovelAlugado') THEN 'VISIT_UNSUCCESSFUL'
        ELSE 'ERROR'
    END AS event_type,
    show_demand.has_attended AS has_demand_attended,
    show_agent.has_attended AS has_agent_attended,
    show_tenant_living.has_attended AS has_tenant_living_attended,
    show_supply.has_attended AS has_supply_attended,
    COALESCE(b.ts_visit_fup, vsl.ts_visit_fup) AS ts_post_visit_agent
FROM
    datalake_ebdb_clean.booking AS b
LEFT JOIN
    visit_status_log AS vsl
        ON b.id = vsl.id_schedule
LEFT JOIN
    datalake_ebdb_clean.visit AS v
        ON b.id_visit = v.id
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
    (b.visit_fup IS NOT NULL OR vsl.visit_fup IS NOT NULL)
    AND b.type = 'Visita'
QUALIFY
    ROW_NUMBER() OVER(PARTITION BY b.id_visit ORDER BY b.id DESC) = 1
