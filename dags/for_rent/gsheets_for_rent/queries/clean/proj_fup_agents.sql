SELECT
    CAST(visitor_id AS BIGINT) AS id_visitor,
    CAST(id_property AS BIGINT) AS id_house,
    CAST(owner_id AS BIGINT) AS id_owner,
    CAST(id_offer AS BIGINT) AS id_offer,
    CAST(agent_id AS BIGINT) AS id_agent,
    region_code,
    offer_status,
    offer_type,
    fup_agents_type,
    gtgc AS gt_gc,
    TO_DATE(offer_sent_date, 'yyyy-MM-dd') AS dt_offer_sent
FROM
    datalake_gsheets_raw.fup_agents_historico
