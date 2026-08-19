-- TQC demand lead referrals — temporary until AAREDE-504.
-- Source: datalake_ebdb_clean.agent_lead_referral
-- Params: {scan_predicate}, {business_context} (SALE = TQC; RENT = TQA later).
-- NULL business_context counts as SALE only (same as dw_agent_accreditation.dim_agent).
--
-- Key trap: agent_lead_referral.id_agent is misnamed — it is legacy id_agent_data
-- (dadosAgent), not accreditation id_agent. Join only to acc.id_agent_data.
-- Never join id_agent_data to id_agent; never join id_agent to id_user.
SELECT
    CAST(acc.id_user AS BIGINT) AS sk_user,
    CAST(acc.id_agent AS BIGINT) AS id_agent,
    bp.ts_created AS ts_event,
    CAST(bp.id_lead_referral AS BIGINT) AS sk_entity,
    'datalake_ebdb_clean.agent_lead_referral.id' AS entity_type
FROM (
    SELECT
        CAST(alr.id_agent AS BIGINT) AS id_agent_data,
        alr.ts_created,
        alr.id AS id_lead_referral,
        alr.status
    FROM
        datalake_ebdb_clean.agent_lead_referral AS alr
    WHERE
        alr.ts_created IS NOT NULL
        AND alr.id_agent IS NOT NULL
        AND COALESCE(alr.status, '') <> 'NOT_ELIGIBLE'
        AND (
            alr.business_context = '{business_context}'
            OR (
                '{business_context}' = 'SALE'
                AND alr.business_context IS NULL
            )
        )
        AND ({scan_predicate})
) AS bp
INNER JOIN
    datalake_agent_accreditation.agent AS acc
        ON CAST(bp.id_agent_data AS STRING) = CAST(acc.id_agent_data AS STRING)
WHERE
    acc.id_user IS NOT NULL
    AND acc.id_agent IS NOT NULL
