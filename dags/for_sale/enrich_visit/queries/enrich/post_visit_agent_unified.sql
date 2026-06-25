WITH old_source AS (
    WITH visit_show AS (
        WITH visit_show_ranked AS (
            SELECT
                vt.id_booking,
                vt.type,
                vt.has_attended,
                ROW_NUMBER() OVER(PARTITION BY vt.id_booking, vt.type ORDER BY vt.ts_created DESC, vt.ts_updated DESC, vt.id DESC) AS rn
            FROM
                datalake_ebdb_clean.visitor AS vt
            JOIN
                datalake_ebdb_clean.visit AS v
                    ON vt.id_visit = v.id
            WHERE
                DATE(v.ts_created) < '2026-06-10'
        )
        SELECT
            id_booking,
            type,
            has_attended
        FROM
            visit_show_ranked
        WHERE
            rn = 1
    ),
    visit_status_log AS ( -- This is to handle the case where the visit_fup is not in the booking table (missing data from visit finalization rollout) so the visit finalization is enriched temporarily from visit_status_log table.
        WITH visit_status_log_ranked AS (
            SELECT
                id_visit,
                id_schedule,
                CASE
                    WHEN event_type = 'VISIT_DONE' THEN 'VaiNegociar'
                    WHEN event_type = 'VISIT_UNSUCCESSFUL' AND reason IN ('DEMAND_DID_NOT_ATTEND_VISIT', 'AGENT_DID_NOT_ATTEND_VISIT', 'SUPPLY_DID_NOT_ATTEND_VISIT') THEN 'NaoCompareceu'
                    WHEN event_type = 'VISIT_UNSUCCESSFUL' AND reason IN ('ACCESS_TO_HOUSE_NOT_AUTHORIZED', 'HOUSE_KEYS_NOT_AVAILABLE', 'HOUSE_NO_LONGER_AVAILABLE_FOR_RENT', 'TENANT_LIVING_DID_NOT_ALLOW_VISIT', 'HOUSE_NO_LONGER_AVAILABLE_FOR_SALE') THEN 'EntradaNaoAutorizada'
                END AS visit_fup,
                ts_created AS ts_visit_fup,
                ROW_NUMBER() OVER(PARTITION BY id_visit ORDER BY id_visit_status_log DESC) AS rn
            FROM
                datalake_visit.visit_status_events
            WHERE
                DATE(ts_created) >= '2025-01-01'
                AND event_type IN ('VISIT_DONE', 'VISIT_UNSUCCESSFUL')
        )
        SELECT
            id_visit,
            id_schedule,
            visit_fup,
            ts_visit_fup
        FROM
            visit_status_log_ranked
        WHERE
            rn = 1
    ),
    old_source_ranked AS (
        SELECT
            b.id_visit,
            b.id AS id_schedule,
            CASE
                WHEN COALESCE(b.visit_fup, vsl.visit_fup) IN ('VaiNegociar', 'NaoGostou', 'VisitouSozinho', 'Talvez') THEN 'VISIT_DONE'
                WHEN COALESCE(b.visit_fup, vsl.visit_fup) IN ('EntradaNaoAutorizada', 'NaoCompareceu', 'ImovelAlugado') THEN 'VISIT_UNSUCCESSFUL'
            END AS event_type,
            CASE
                WHEN b.visit_fup = 'EntradaNaoAutorizada' THEN 'ACCESS_TO_HOUSE_NOT_AUTHORIZED'
                WHEN b.visit_fup = 'NaoCompareceu' AND show_demand.has_attended = FALSE THEN 'DEMAND_DID_NOT_ATTEND_VISIT'
                WHEN b.visit_fup = 'NaoCompareceu' AND show_agent.has_attended = FALSE THEN 'AGENT_DID_NOT_ATTEND_VISIT'
                WHEN b.visit_fup = 'NaoCompareceu' AND show_supply.has_attended = FALSE THEN 'SUPPLY_DID_NOT_ATTEND_VISIT'
                WHEN b.visit_fup = 'ImovelAlugado' AND v.business_context = 'RENT' THEN 'HOUSE_NO_LONGER_AVAILABLE_FOR_RENT'
                WHEN b.visit_fup = 'ImovelAlugado' AND v.business_context = 'SALE' THEN 'HOUSE_NO_LONGER_AVAILABLE_FOR_SALE'
                ELSE NULL
            END AS unsuccessful_reason_migrated,
            IF(event_type = 'VISIT_UNSUCCESSFUL', COALESCE(unsuccessful_reason_migrated, vsl.visit_fup), NULL) AS unsuccessful_reason,
            IF(event_type = 'VISIT_UNSUCCESSFUL' AND show_demand.has_attended = FALSE, TRUE, FALSE) AS has_unsuccessful_demand_not_attended,
            IF(event_type = 'VISIT_UNSUCCESSFUL' AND show_agent.has_attended = FALSE, TRUE, FALSE) AS has_unsuccessful_agent_not_attended,
            IF(event_type = 'VISIT_UNSUCCESSFUL' AND show_supply.has_attended = FALSE, TRUE, FALSE) AS has_unsuccessful_supply_not_attended,
            COALESCE(b.ts_visit_fup, vsl.ts_visit_fup) AS ts_post_visit_agent,
            ROW_NUMBER() OVER(PARTITION BY b.id_visit ORDER BY b.id DESC) AS rn
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
            AND DATE(v.ts_created) < '2026-06-10'
    )
    SELECT
        id_visit,
        id_schedule,
        event_type,
        unsuccessful_reason_migrated,
        unsuccessful_reason,
        has_unsuccessful_demand_not_attended,
        has_unsuccessful_agent_not_attended,
        has_unsuccessful_supply_not_attended,
        ts_post_visit_agent
    FROM
        old_source_ranked
    WHERE
        rn = 1
),
new_source AS (
    WITH new_source_ranked AS (
        SELECT
            vse.id_visit,
            vse.id_schedule,
            IF(vse.event_type = 'VISIT_UNSUCCESSFUL', vse.reason, NULL) AS unsuccessful_reason,
            vse.event_type,
            vse.channel,
            IF(vse.event_type = 'VISIT_UNSUCCESSFUL' AND vse.reason = 'DEMAND_DID_NOT_ATTEND_VISIT', TRUE, FALSE) AS has_unsuccessful_demand_not_attended,
            IF(vse.event_type = 'VISIT_UNSUCCESSFUL' AND vse.reason = 'AGENT_DID_NOT_ATTEND_VISIT', TRUE, FALSE) AS has_unsuccessful_agent_not_attended,
            IF(vse.event_type = 'VISIT_UNSUCCESSFUL' AND vse.reason = 'SUPPLY_DID_NOT_ATTEND_VISIT', TRUE, FALSE) AS has_unsuccessful_supply_not_attended,
            vse.ts_created AS ts_post_visit_agent,
            ROW_NUMBER() OVER(PARTITION BY vse.id_visit ORDER BY vse.ts_created DESC, vse.id_visit_status_log DESC) AS rn
        FROM
            datalake_visit.visit_status_events AS vse
        JOIN
            datalake_ebdb_clean.visit AS v
                ON vse.id_visit = v.id
        WHERE
            vse.event_type IN ('VISIT_DONE', 'VISIT_UNSUCCESSFUL')
            AND DATE(v.ts_created) >= '2026-06-10'
    )
    SELECT
        id_visit,
        id_schedule,
        unsuccessful_reason,
        event_type,
        channel,
        has_unsuccessful_demand_not_attended,
        has_unsuccessful_agent_not_attended,
        has_unsuccessful_supply_not_attended,
        ts_post_visit_agent
    FROM
        new_source_ranked
    WHERE
        rn = 1
)
SELECT
    id_visit,
    id_schedule,
    unsuccessful_reason,
    event_type,
    NULL AS channel,
    has_unsuccessful_demand_not_attended,
    has_unsuccessful_agent_not_attended,
    has_unsuccessful_supply_not_attended,
    ts_post_visit_agent
FROM old_source
UNION ALL
SELECT
    id_visit,
    id_schedule,
    unsuccessful_reason,
    event_type,
    channel,
    has_unsuccessful_demand_not_attended,
    has_unsuccessful_agent_not_attended,
    has_unsuccessful_supply_not_attended,
    ts_post_visit_agent
FROM new_source
