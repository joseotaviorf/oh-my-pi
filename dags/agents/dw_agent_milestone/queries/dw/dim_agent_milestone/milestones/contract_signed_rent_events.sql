-- First CS (signed rent contract) from enrich rent_demand_events.
-- Same upstream as agent_offers rent branch: id_event_type = 9 (contract signed).
-- Params: {scan_predicate}
--
-- Key trap: rent_demand_events.id_agent is misnamed — enrich fills it from
-- id_user_agent (platform id_user). Never join *.id_agent to *.id_user by name;
-- rename to id_user_agent first, then join accreditation on id_user.
-- id_agent_data (legacy) ≠ id_agent (accreditation) — do not mix those either.
SELECT
    CAST(acc.id_user AS BIGINT) AS sk_user,
    CAST(acc.id_agent AS BIGINT) AS id_agent,
    cs.ts_event AS ts_event,
    CAST(COALESCE(cs.id_contract, cs.id_offer, -1) AS BIGINT) AS sk_entity,
    'datalake_rent_demand_events.rent_demand_events.id_contract' AS entity_type
FROM (
    SELECT
        CAST(rde.id_agent AS BIGINT) AS id_user_agent,
        rde.ts_event,
        rde.id_contract,
        rde.id_offer
    FROM
        datalake_rent_demand_events.rent_demand_events AS rde
    WHERE
        rde.id_event_type = 9
        AND rde.id_agent IS NOT NULL
        AND rde.ts_event IS NOT NULL
        AND ({scan_predicate})
) AS cs
INNER JOIN
    datalake_agent_accreditation.agent AS acc
        ON CAST(cs.id_user_agent AS STRING) = CAST(acc.id_user AS STRING)
WHERE
    acc.id_user IS NOT NULL
    AND acc.id_agent IS NOT NULL
