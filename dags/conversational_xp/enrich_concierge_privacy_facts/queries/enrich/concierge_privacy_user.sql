WITH exploded_purpose_acceptances AS (
    SELECT
        TRY_CAST(data_subject.id_external AS BIGINT) AS id_user,
        purpose_acceptance.alias AS purpose_alias,
        purpose_acceptance.status AS purpose_status,
        purpose_acceptance.updatedAt AS ts_purpose_updated
    FROM (
        SELECT
            id_external,
            FROM_JSON(
                purpose_acceptances,
                'ARRAY<STRUCT<alias: STRING, status: STRING, purpose: INT, version: STRING, document: STRING, updatedAt: TIMESTAMP>>'
            ) AS purpose_acceptances_struct
        FROM
            datalake_privacy_hub_clean.data_subject
        WHERE
            COALESCE(is_deleted, FALSE) = FALSE
            AND (
                CONTAINS(purpose_acceptances, 'SNOOZE_CONCIERGE')
                OR CONTAINS(purpose_acceptances, 'TENANT_MESSAGE_AI_INFORMATIVE')
            )
    ) AS data_subject
    LATERAL VIEW EXPLODE(data_subject.purpose_acceptances_struct) AS purpose_acceptance
    WHERE
        purpose_acceptance.alias IN (
            'SNOOZE_CONCIERGE',
            'TENANT_MESSAGE_AI_INFORMATIVE'
        )
        AND TRY_CAST(data_subject.id_external AS BIGINT) IS NOT NULL
),
latest_purpose_acceptances AS (
    SELECT
        ranked.id_user,
        ranked.purpose_alias,
        ranked.purpose_status,
        ranked.ts_purpose_updated
    FROM (
        SELECT
            id_user,
            purpose_alias,
            purpose_status,
            ts_purpose_updated,
            ROW_NUMBER() OVER (
                PARTITION BY id_user, purpose_alias
                ORDER BY ts_purpose_updated DESC, purpose_status DESC
            ) AS rn
        FROM
            exploded_purpose_acceptances
    ) AS ranked
    WHERE
        ranked.rn = 1
),
current_privacy_state AS (
    SELECT
        id_user,
        MAX(
            CASE
                WHEN purpose_alias = 'SNOOZE_CONCIERGE'
                THEN purpose_status
            END
        ) AS snooze_concierge_status,
        MAX(
            CASE
                WHEN purpose_alias = 'TENANT_MESSAGE_AI_INFORMATIVE'
                THEN purpose_status
            END
        ) AS tenant_message_ai_informative_status,
        MAX(
            CASE
                WHEN purpose_alias = 'SNOOZE_CONCIERGE'
                THEN ts_purpose_updated
            END
        ) AS ts_snooze_concierge_updated,
        MAX(
            CASE
                WHEN purpose_alias = 'TENANT_MESSAGE_AI_INFORMATIVE'
                THEN ts_purpose_updated
            END
        ) AS ts_tenant_message_ai_informative_updated,
        COALESCE(
            MAX(
                purpose_alias = 'SNOOZE_CONCIERGE'
                AND purpose_status = 'ACTIVE'
            ),
            FALSE
        ) AS is_snooze_concierge_active,
        COALESCE(
            MAX(
                purpose_alias = 'TENANT_MESSAGE_AI_INFORMATIVE'
                AND purpose_status = 'WITHDRAWN'
            ),
            FALSE
        ) AS is_tenant_message_ai_informative_withdrawn,
        COALESCE(
            MAX(
                purpose_alias = 'SNOOZE_CONCIERGE'
                AND purpose_status = 'ACTIVE'
            ),
            FALSE
        )
        OR COALESCE(
            MAX(
                purpose_alias = 'TENANT_MESSAGE_AI_INFORMATIVE'
                AND purpose_status = 'WITHDRAWN'
            ),
            FALSE
        ) AS is_concierge_privacy_suppressed
    FROM
        latest_purpose_acceptances
    GROUP BY
        id_user
),
mapped_privacy_state AS (
    SELECT
        privacy_state.id_user,
        cdp_user.id_person,
        privacy_state.snooze_concierge_status,
        privacy_state.tenant_message_ai_informative_status,
        privacy_state.ts_snooze_concierge_updated,
        privacy_state.ts_tenant_message_ai_informative_updated,
        privacy_state.is_snooze_concierge_active,
        privacy_state.is_tenant_message_ai_informative_withdrawn,
        privacy_state.is_concierge_privacy_suppressed
    FROM
        current_privacy_state AS privacy_state
    INNER JOIN
        datalake_cdp.users AS cdp_user
            ON cdp_user.id_user = privacy_state.id_user
    WHERE
        cdp_user.id_person IS NOT NULL
)
SELECT
    ranked.id_user,
    ranked.id_person,
    ranked.snooze_concierge_status,
    ranked.tenant_message_ai_informative_status,
    ranked.ts_snooze_concierge_updated,
    ranked.ts_tenant_message_ai_informative_updated,
    ranked.is_snooze_concierge_active,
    ranked.is_tenant_message_ai_informative_withdrawn,
    ranked.is_concierge_privacy_suppressed,
    YEAR(CURRENT_DATE()) AS year,
    MONTH(CURRENT_DATE()) AS month,
    DAY(CURRENT_DATE()) AS day
FROM (
    SELECT
        mapped_privacy_state.id_user,
        mapped_privacy_state.id_person,
        mapped_privacy_state.snooze_concierge_status,
        mapped_privacy_state.tenant_message_ai_informative_status,
        mapped_privacy_state.ts_snooze_concierge_updated,
        mapped_privacy_state.ts_tenant_message_ai_informative_updated,
        mapped_privacy_state.is_snooze_concierge_active,
        mapped_privacy_state.is_tenant_message_ai_informative_withdrawn,
        mapped_privacy_state.is_concierge_privacy_suppressed,
        ROW_NUMBER() OVER (
            PARTITION BY mapped_privacy_state.id_person
            ORDER BY
                mapped_privacy_state.is_concierge_privacy_suppressed DESC,
                COALESCE(
                    mapped_privacy_state.ts_snooze_concierge_updated,
                    CAST('1970-01-01 00:00:00' AS TIMESTAMP)
                ) DESC,
                COALESCE(
                    mapped_privacy_state.ts_tenant_message_ai_informative_updated,
                    CAST('1970-01-01 00:00:00' AS TIMESTAMP)
                ) DESC,
                mapped_privacy_state.id_user DESC
        ) AS rn
    FROM
        mapped_privacy_state
) AS ranked
WHERE
    ranked.rn = 1
