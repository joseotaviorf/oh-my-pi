-- First CCV (signed sale agreement) from enrich sale_offer (broker / visit agent).
-- Same upstream as agent_offers sale AGENT branch: id_user_agent + ts_sale_agreement_signed.
-- Params: {scan_predicate}
-- Identity: sk_user = id_user_agent; id_agent from datalake_agent_accreditation.agent.
SELECT
    CAST(acc.id_user AS BIGINT) AS sk_user,
    CAST(acc.id_agent AS BIGINT) AS id_agent,
    so.ts_sale_agreement_signed AS ts_event,
    CAST(so.id_offer AS BIGINT) AS sk_entity,
    'datalake_sale_offer.sale_offer.id_offer' AS entity_type
FROM
    datalake_sale_offer.sale_offer AS so
INNER JOIN
    datalake_agent_accreditation.agent AS acc
        ON CAST(so.id_user_agent AS STRING) = CAST(acc.id_user AS STRING)
WHERE
    so.id_user_agent IS NOT NULL
    AND so.ts_sale_agreement_signed IS NOT NULL
    AND acc.id_agent IS NOT NULL
    AND ({scan_predicate})
