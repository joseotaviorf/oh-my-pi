-- Source: trato_feito runs at 0 3,8,12 * * *; entity is not updated every 30 mins. Revisit if 30-min cadence is needed.
WITH late_fee_discount_audiences AS (
    SELECT DISTINCT
        ano.id_audience
    FROM
        datalake_trato_feito_clean.audience_negotiation_option AS ano
    INNER JOIN
        datalake_trato_feito_clean.negotiation_option AS neg_option
            ON ano.id_negotiation_option = neg_option.id_negotiation_option
    WHERE
        ano.is_active = TRUE
        AND neg_option.discount_on_fee_percent = 100.00
        AND neg_option.discount_on_fine_percent = 100.00
),
customer_segmentation AS (
    SELECT
        csd.id_customer_segment_distribution AS id_entity,
        csd.customer_document_type,
        csd.customer_document_value,
        csd.id_priority_contract,
        CASE
            WHEN csd.is_active = FALSE THEN 'debts_settled'
            WHEN s.name LIKE 'EVICTIONS%' AND s.is_active = TRUE THEN 'is_on_evictions'
            WHEN s.name LIKE 'ACTIVE_STOCK_RISK%' AND s.is_active = TRUE THEN 'is_on_pre_evictions'
            WHEN lfd.id_audience IS NOT NULL THEN 'has_late_fee_discount'
            ELSE 'is_segmented'
        END AS status,
        csd.ts_created,
        csd.ts_updated
    FROM
        datalake_trato_feito_clean.customer_segment_distribution AS csd
    LEFT JOIN
        datalake_trato_feito_clean.segment AS s
            ON csd.id_segment = s.id_segment
    LEFT JOIN
        late_fee_discount_audiences AS lfd
            ON csd.id_audience = lfd.id_audience
),
trato_feito_client_ranked AS (
    SELECT
        segmentation.id_entity,
        client.id_external,
        ROW_NUMBER() OVER (
            PARTITION BY segmentation.id_entity
            ORDER BY
                CASE
                    WHEN NULLIF(TRIM(CAST(client.id_external AS STRING)), '') IS NOT NULL
                    THEN 0
                    ELSE 1
                END,
                client.ts_created DESC
        ) AS client_rank
    FROM
        customer_segmentation AS segmentation
    INNER JOIN
        datalake_trato_feito_clean.client AS client
            ON LOWER(client.document_type) = LOWER(segmentation.customer_document_type)
            AND client.document = segmentation.customer_document_value
            AND client.deleted = FALSE
            AND client.client_type <> 'landlord'
),
trato_feito_client AS (
    SELECT
        id_entity,
        id_external
    FROM
        trato_feito_client_ranked
    WHERE
        client_rank = 1
),
ebdb_user_by_external_id AS (
    SELECT
        client.id_entity,
        ebdb_user.id AS id_user
    FROM
        trato_feito_client AS client
    INNER JOIN
        datalake_ebdb_clean.user AS ebdb_user
            ON ebdb_user.id = TRY_CAST(NULLIF(TRIM(CAST(client.id_external AS STRING)), '') AS BIGINT)
),
ebdb_user_by_cpf_hash_ranked AS (
    SELECT
        segmentation.id_entity,
        ebdb_user.id AS id_user,
        ROW_NUMBER() OVER (
            PARTITION BY segmentation.id_entity
            ORDER BY ebdb_user.id DESC
        ) AS cpf_hash_rank
    FROM
        customer_segmentation AS segmentation
    INNER JOIN
        datalake_ebdb_clean.user AS ebdb_user
            ON ebdb_user.cpf = segmentation.customer_document_value
),
ebdb_user_by_cpf_hash AS (
    SELECT
        id_entity,
        id_user
    FROM
        ebdb_user_by_cpf_hash_ranked
    WHERE
        cpf_hash_rank = 1
),
collections_segment_resolved AS (
    SELECT
        segmentation.id_entity,
        contract.id_house,
        contract.id_contract,
        COALESCE(
            user_by_external_id.id_user,
            user_by_cpf_hash.id_user
        ) AS id_user,
        segmentation.status,
        segmentation.ts_created,
        segmentation.ts_updated
    FROM
        customer_segmentation AS segmentation
    LEFT JOIN
        core_contract.contract AS contract
            ON CAST(segmentation.id_priority_contract AS BIGINT) = contract.id_contract
    LEFT JOIN
        ebdb_user_by_external_id AS user_by_external_id
            ON segmentation.id_entity = user_by_external_id.id_entity
    LEFT JOIN
        ebdb_user_by_cpf_hash AS user_by_cpf_hash
            ON segmentation.id_entity = user_by_cpf_hash.id_entity
    WHERE
        contract.id_contract IS NOT NULL
        -- a null id_user fails `> 0` as well, so this drops unresolved users too
        AND COALESCE(user_by_external_id.id_user, user_by_cpf_hash.id_user) > 0
)
SELECT
    id_entity,
    id_house,
    id_contract,
    id_user,
    'FR_COLLECTIONS_SEGMENT' AS entity,
    'RENT' AS business_context,
    'TENANT' AS persona,
    TO_JSON(
        STRUCT(
            status AS status,
            ts_created AS when
        )
    ) AS properties,
    -- debts_settled is the only inactive status; all others mean the customer is still in collections
    CASE
        WHEN status = 'debts_settled' THEN FALSE
        ELSE TRUE
    END AS is_active,
    ts_created,
    ts_updated
FROM
    collections_segment_resolved
