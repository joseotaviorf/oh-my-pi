WITH broker_map AS (
  SELECT DISTINCT
    uuid_company,
    CAST(id AS VARCHAR) AS sk_broker
  FROM datalake_company_clean.company
)
SELECT
  aai.uuid_ai_agent                           AS sk_ai_agent,
  bm.sk_broker,
  aai.agent_name,
  aai.display_name,
  aai.twilio_account_sid,
  aai.twilio_phone_number,
  -- Excluded: twilio_auth_token, twilio_api_secret, twilio_auth_token_plain,
  --            twilio_api_secret_plain, id_twilio_api_key (sensitive credentials)
  aai.ts_phone_verified IS NOT NULL           AS is_phone_verified,
  aai.ts_phone_verified,
  aai.ts_created,
  aai.ts_updated,
  CURRENT_TIMESTAMP()                         AS ts_load,
  YEAR(aai.ts_updated)                        AS year,
  MONTH(aai.ts_updated)                       AS month,
  DAY(aai.ts_updated)                         AS day
FROM datalake_alias_clean.ai_agents AS aai
LEFT JOIN broker_map AS bm ON aai.uuid_company = bm.uuid_company
WHERE '{load_start_date}' <= aai.ts_updated
  AND aai.ts_updated < '{load_end_date}'
