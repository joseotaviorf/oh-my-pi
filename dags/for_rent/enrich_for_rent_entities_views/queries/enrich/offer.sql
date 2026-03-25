WITH offer_base AS (
    SELECT
        id_offer AS id_entity,
        id_house,
        CAST(NULL AS BIGINT) AS id_contract,
        id_tenant,
        id_owner,
        'FR_OFFER' AS entity,
        'RENT' AS business_context,
        TO_JSON(
            STRUCT(
                status AS status,
                ts_expiration AS when
            )
        ) AS properties,
        CASE
            WHEN status = 'PROPOSED' THEN TRUE
            WHEN status IN ('ACCEPTED', 'DISMISSED', 'REJECTED') THEN FALSE
            ELSE NULL
        END AS is_active,
        ts_created,
        ts_updated
    FROM
        core_offer.offer
)
SELECT
    id_entity,
    id_house,
    id_contract,
    id_tenant AS id_user,
    entity,
    'TENANT_PROSPECT' AS persona,
    business_context,
    properties,
    is_active,
    ts_created,
    ts_updated
FROM
    offer_base
UNION ALL
SELECT
    id_entity,
    id_house,
    id_contract,
    id_owner AS id_user,
    entity,
    'OWNER' AS persona,
    business_context,
    properties,
    is_active,
    ts_created,
    ts_updated
FROM
    offer_base
