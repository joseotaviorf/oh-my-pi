SELECT
    CAST(tp_id AS BIGINT) AS id_visitor,
    CAST(imovel_id AS BIGINT) AS id_house,
    CAST(owner_id AS BIGINT) AS id_owner,
    CAST(offer_id AS BIGINT) AS id_offer,
    CAST(agent_id AS BIGINT) AS id_agent,
    region_code,
    offer_status,
    type_offer AS offer_type,
    fup_agents_type,
    gt_gc,
    TO_DATE(os_date, 'yyyy-MM-dd') AS dt_offer_sent
FROM
    datalake_gsheets_raw.fup_agents_historico
