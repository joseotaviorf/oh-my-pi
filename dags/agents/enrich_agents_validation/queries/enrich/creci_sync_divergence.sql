/* Compares CRECI across DadosAgente, Partner, and Person per agent, gated on the
agent actually having each linked record. Comparison is case/blank-insensitive
(TRIM + UPPER, NULL and blank treated the same). Scoped to ACTIVE agents only —
a person has at most one ACTIVE agent record, which keeps the grain at one row
per uuid_person without needing extra aggregation. Never returns the raw CRECI,
only ids and divergence flags. */
WITH agent_external_reference AS (
    SELECT
        aer.id_agent,
        FIRST(aer.value) FILTER(WHERE aer.type = 'DADOS_AGENTE_ID') AS id_agent_data,
        FIRST(aer.value) FILTER(WHERE aer.type = 'PARTNER_ID') AS id_partner
    FROM
        datalake_ebdb_clean.agent_external_reference AS aer
    GROUP BY 1
),
agent AS (
    SELECT
        a.id AS id_agent,
        a.uuid_person,
        aer.id_agent_data,
        aer.id_partner
    FROM
        datalake_ebdb_clean.agent AS a
    LEFT JOIN
        agent_external_reference AS aer
            ON aer.id_agent = a.id
    WHERE
        a.status = 'ACTIVE'
),
agent_data_creci AS (
    SELECT
        ad.id,
        ad.creci_number
    FROM
        datalake_ebdb_clean.agent_data AS ad
    WHERE
        ad.id IN (SELECT id_agent_data FROM agent WHERE id_agent_data IS NOT NULL)
),
partner_creci AS (
    SELECT
        p.id,
        p.creci
    FROM
        datalake_ebdb_clean.partner AS p
    WHERE
        p.id IN (SELECT id_partner FROM agent WHERE id_partner IS NOT NULL)
),
person_creci AS (
    SELECT
        p.uuid_person,
        idoc.identification_number
    FROM
        datalake_person_clean.person AS p
    JOIN
        datalake_person_clean.identity_document AS idoc
            ON idoc.id_person = p.id
            AND idoc.document_type = 'CRECI'
    WHERE
        p.uuid_person IN (SELECT uuid_person FROM agent)
),
creci_divergence AS (
    SELECT
        a.uuid_person,
        a.id_agent,
        a.id_agent_data,
        a.id_partner,
        a.id_agent_data IS NOT NULL AND NULLIF(TRIM(adc.creci_number), '') IS NULL AS is_agent_data_missing_creci,
        a.id_partner IS NOT NULL AND NULLIF(TRIM(pc.creci), '') IS NULL AS is_partner_missing_creci,
        NULLIF(TRIM(pec.identification_number), '') IS NULL AS is_person_missing_creci,
        a.id_agent_data IS NOT NULL
            AND COALESCE(UPPER(TRIM(adc.creci_number)), '') <> COALESCE(UPPER(TRIM(pec.identification_number)), '')
            AS is_agent_data_vs_person_divergent,
        a.id_partner IS NOT NULL
            AND COALESCE(UPPER(TRIM(pc.creci)), '') <> COALESCE(UPPER(TRIM(pec.identification_number)), '')
            AS is_partner_vs_person_divergent,
        a.id_agent_data IS NOT NULL
            AND a.id_partner IS NOT NULL
            AND COALESCE(UPPER(TRIM(adc.creci_number)), '') <> COALESCE(UPPER(TRIM(pc.creci)), '')
            AS is_agent_data_vs_partner_divergent
    FROM
        agent AS a
    LEFT JOIN
        agent_data_creci AS adc
            ON adc.id = a.id_agent_data
    LEFT JOIN
        partner_creci AS pc
            ON pc.id = a.id_partner
    LEFT JOIN
        person_creci AS pec
            ON pec.uuid_person = a.uuid_person
)
SELECT
    uuid_person,
    id_agent,
    id_agent_data,
    id_partner,
    is_agent_data_missing_creci,
    is_partner_missing_creci,
    is_person_missing_creci,
    is_agent_data_vs_person_divergent,
    is_partner_vs_person_divergent,
    is_agent_data_vs_partner_divergent,
    CURRENT_TIMESTAMP() AS ts_validated
FROM
    creci_divergence
WHERE
    is_agent_data_vs_person_divergent
    OR is_partner_vs_person_divergent
    OR is_agent_data_vs_partner_divergent
UNION ALL
SELECT
    NULL AS uuid_person,
    NULL AS id_agent,
    NULL AS id_agent_data,
    NULL AS id_partner,
    FALSE AS is_agent_data_missing_creci,
    FALSE AS is_partner_missing_creci,
    FALSE AS is_person_missing_creci,
    FALSE AS is_agent_data_vs_person_divergent,
    FALSE AS is_partner_vs_person_divergent,
    FALSE AS is_agent_data_vs_partner_divergent,
    CURRENT_TIMESTAMP() AS ts_validated
