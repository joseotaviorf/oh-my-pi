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
customers_with_active_segmentation AS (
    SELECT DISTINCT
        customer_document_type,
        customer_document_value,
        id_priority_contract
    FROM
        datalake_trato_feito_clean.customer_segment_distribution
    WHERE
        is_active = TRUE
),
collections_segment_client_ranked AS (
    SELECT
        csd.id_customer_segment_distribution AS id_entity,
        ct.id_house,
        ct.id_contract,
        cl.id_external,
        csd.customer_document_value,
        CAST(csd.id_priority_contract AS BIGINT) AS id_priority_contract,
        'FR_COLLECTIONS_SEGMENT' AS entity,
        'RENT' AS business_context,
        CASE
            WHEN active_segmentation.id_priority_contract IS NULL THEN 'debts_settled'
            WHEN s.name = 'EVICTIONS' AND s.is_active = TRUE THEN 'is_on_evictions'
            WHEN s.name IN (
                'ACTIVE_STOCK_RISK_DEAL_LOW',
                'ACTIVE_STOCK_RISK_DEAL_HIGH',
                'ACTIVE_STOCK_RISK_NODEAL_LOW',
                'ACTIVE_STOCK_RISK_NODEAL_HIGH'
            ) AND s.is_active = TRUE THEN 'is_on_pre_evictions'
            WHEN lfd.id_audience IS NOT NULL THEN 'has_late_fee_discount'
            ELSE 'is_segmented'
        END AS status,
        csd.ts_created,
        csd.ts_updated,
        ROW_NUMBER() OVER (
            PARTITION BY csd.id_customer_segment_distribution
            ORDER BY
                CASE
                    WHEN cl.id_external IS NOT NULL
                        AND NULLIF(TRIM(CAST(cl.id_external AS STRING)), '') IS NOT NULL
                    THEN 0
                    ELSE 1
                END,
                cl.ts_created DESC
        ) AS client_rank
    FROM
        datalake_trato_feito_clean.customer_segment_distribution AS csd
    INNER JOIN
        datalake_trato_feito_clean.client AS cl
            ON LOWER(cl.document_type) = LOWER(csd.customer_document_type)
            AND cl.document = csd.customer_document_value
            AND cl.deleted = FALSE
            AND cl.client_type <> 'landlord'
    LEFT JOIN
        customers_with_active_segmentation AS active_segmentation
            ON csd.customer_document_type = active_segmentation.customer_document_type
            AND csd.customer_document_value = active_segmentation.customer_document_value
    LEFT JOIN
        datalake_trato_feito_clean.segment AS s
            ON csd.id_segment = s.id_segment
    LEFT JOIN
        late_fee_discount_audiences AS lfd
            ON csd.id_audience = lfd.id_audience
    INNER JOIN
        core_contract.contract AS ct
            ON CAST(csd.id_priority_contract AS BIGINT) = ct.id_contract
    WHERE
        csd.is_active = TRUE
        OR active_segmentation.id_priority_contract IS NULL
),
collections_segment_client AS (
    SELECT
        id_entity,
        id_house,
        id_contract,
        id_external,
        customer_document_value,
        id_priority_contract,
        entity,
        business_context,
        status,
        ts_created,
        ts_updated
    FROM
        collections_segment_client_ranked
    WHERE
        client_rank = 1
),
cpf_hash_user_ranked AS (
    SELECT
        base.id_entity,
        u_cpf.id AS id_user_cpf_hash,
        ROW_NUMBER() OVER (
            PARTITION BY base.id_entity
            ORDER BY u_cpf.id DESC
        ) AS cpf_hash_user_rank
    FROM
        collections_segment_client AS base
    INNER JOIN
        datalake_ebdb_clean.user AS u_cpf
            ON u_cpf.cpf = base.customer_document_value
),
cpf_hash_user AS (
    SELECT
        id_entity,
        id_user_cpf_hash
    FROM
        cpf_hash_user_ranked
    WHERE
        cpf_hash_user_rank = 1
),
collections_segment_resolved AS (
    SELECT
        base.id_entity,
        base.id_house,
        base.id_contract,
        COALESCE(
            CASE
                WHEN u_ext.id IS NOT NULL
                THEN TRY_CAST(NULLIF(TRIM(CAST(base.id_external AS STRING)), '') AS BIGINT)
            END,
            chu.id_user_cpf_hash
        ) AS id_user,
        base.entity,
        base.business_context,
        base.status,
        base.ts_created,
        base.ts_updated
    FROM
        collections_segment_client AS base
    LEFT JOIN
        datalake_ebdb_clean.user AS u_ext
            ON u_ext.id = TRY_CAST(NULLIF(TRIM(CAST(base.id_external AS STRING)), '') AS BIGINT)
    LEFT JOIN
        cpf_hash_user AS chu
            ON base.id_entity = chu.id_entity
),
collections_segment_base AS (
    SELECT
        id_entity,
        id_house,
        id_contract,
        id_user,
        entity,
        business_context,
        status,
        ts_created,
        ts_updated
    FROM
        collections_segment_resolved
    WHERE
        id_user IS NOT NULL
        AND NULLIF(TRIM(CAST(id_user AS STRING)), '') IS NOT NULL
        AND id_user > 0
)
SELECT
    id_entity,
    id_house,
    id_contract,
    id_user,
    entity,
    'TENANT' AS persona,
    business_context,
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
    collections_segment_base
