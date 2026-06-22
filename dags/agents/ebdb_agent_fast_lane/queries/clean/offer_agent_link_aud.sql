SELECT
    id,
    offer_id AS id_offer,
    agent_uuid AS uuid_agent,
    REV AS rev,
    REVTYPE AS rev_type,
    offer_source,
    created_at AS ts_created,
    id_MOD AS mod_id,
    offer_id_MOD AS mod_id_offer,
    agent_uuid_MOD AS mod_uuid_agent,
    offer_source_MOD AS mod_offer_source
FROM
    datalake_ebdb_raw.OfferAgentLink_AUD
