SELECT
    aai.uuid_ai_agent AS sk_ai_agent,
    COALESCE(cb.sk_broker, -1) AS sk_broker,
    aai.agent_name,
    aai.display_name,
    aai.twilio_account_sid,
    aai.twilio_phone_number,
    aai.ts_phone_verified IS NOT NULL AS is_phone_verified,
    aai.ts_phone_verified,
    aai.ts_created,
    aai.ts_updated,
    CURRENT_TIMESTAMP() AS ts_load,
    YEAR(aai.ts_updated) AS year,
    MONTH(aai.ts_updated) AS month,
    DAY(aai.ts_updated) AS day
FROM
    datalake_alias_clean.ai_agents AS aai
LEFT JOIN
    core_brokers.brokers AS cb
        ON aai.uuid_company = cb.uuid_company