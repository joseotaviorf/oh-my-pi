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
collections_segment_base AS (
    SELECT
        csd.id_contract_segment_distribution AS id_entity,
        ct.id_house,
        ct.id_contract,
        ct.id_tenant,
        'FR_COLLECTIONS_SEGMENT' AS entity,
        'RENT' AS business_context,
        CASE
            WHEN csd.is_active = FALSE THEN 'debts_settled'
            WHEN s.name = 'EVICTIONS' AND s.is_active = TRUE THEN 'is_on_evictions'
            WHEN s.name LIKE '%STOCK_RISK%' AND s.is_active = TRUE THEN 'is_on_pre_evictions'
            WHEN lfd.id_audience IS NOT NULL THEN 'has_late_fee_discount'
            ELSE 'is_segmented'
        END AS status,
        csd.ts_created,
        csd.ts_updated
    FROM
        datalake_trato_feito_clean.contract_segment_distribution AS csd
    LEFT JOIN
        datalake_trato_feito_clean.segment AS s
            ON csd.id_segment = s.id_segment
    LEFT JOIN
        late_fee_discount_audiences AS lfd
            ON csd.id_audience = lfd.id_audience
    INNER JOIN
        core_contract.contract AS ct
            ON CAST(csd.id_contract AS BIGINT) = ct.id_contract
)
SELECT
    id_entity,
    id_house,
    id_contract,
    id_tenant AS id_user,
    entity,
    'TENANT' AS persona,
    business_context,
    TO_JSON(
        STRUCT(
            status AS status,
            ts_created AS when
        )
    ) AS properties,
    status != 'debts_settled' AS is_active,
    ts_created,
    ts_updated
FROM
    collections_segment_base
