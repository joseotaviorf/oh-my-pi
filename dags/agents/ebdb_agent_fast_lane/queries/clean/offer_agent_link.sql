SELECT
    id,
    offer_id AS id_offer,
    agent_uuid AS uuid_agent,
    offer_source,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
    datalake_ebdb_raw.OfferAgentLink
