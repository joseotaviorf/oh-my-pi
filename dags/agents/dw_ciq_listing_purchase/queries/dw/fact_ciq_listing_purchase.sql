WITH house_sale_agreement AS (
    SELECT
        so.id_house,
        MAX(so.ts_sale_agreement_signed) AS ts_last_sale_agreement_signed
    FROM
        datalake_sale_offer.sale_offer AS so
    WHERE
        so.ts_sale_agreement_signed IS NOT NULL
        AND COALESCE(so.is_ccv_canceled, FALSE) = FALSE
    GROUP BY
        so.id_house
),
portfolio_loss_flags AS (
    SELECT
        clp.id_listing_purchase,
        COALESCE(
            clp.listing_category = 'Re-Listing'
            AND clp.ts_contract_signed IS NULL
            AND clp.listing_status IN ('PUBLISHED', 'PUBLICADO')
            AND clp.total_days_since_publish > 90,
            FALSE
        ) AS is_relisting_without_contract_90d,
        -- id_house with non-canceled CCV after a rent CS in compra de carteira era
        -- (CS >= 2026-07-01). Pre-July CS + later CCV is not loss (Rafael / AAREDE-521).
        -- Rules are mutually exclusive on one row (90d needs null CS; CCV needs CS).
        COALESCE(
            clp.ts_contract_signed IS NOT NULL
            AND clp.ts_contract_signed >= DATE('2026-07-01')
            AND hsa.ts_last_sale_agreement_signed IS NOT NULL
            AND hsa.ts_last_sale_agreement_signed > clp.ts_contract_signed,
            FALSE
        ) AS is_ccv_after_post_july_rent_cs
    FROM
        datalake_ciq.ciq_listing_purchase AS clp
    LEFT JOIN
        house_sale_agreement AS hsa
            ON hsa.id_house = clp.id_house
),
-- Partner-facing PT map (broadcast); unknown EN kept as-is via COALESCE below.
partner_reason_map AS (
    SELECT
        reason_en,
        reason_pt
    FROM
        VALUES
            ('Business context is not RENT', 'Contexto de negócio não é aluguel (RENT)'),
            ('User consultant is not CIQ_FULL', 'Consultor do usuário não é CIQ_FULL'),
            ('Don''t have a contract signed yet', 'Ainda sem contrato assinado'),
            (
                'Contract signed before the transition',
                'Contrato assinado antes da transição de contrato (compra de carteira)'
            ),
            (
                'House is a hybrid house converted from sale to rent',
                'Imóvel híbrido convertido de venda para aluguel'
            ),
            (
                'House listing published and rented after the transition',
                'Anúncio publicado e alugado após a transição de contrato (compra de carteira)'
            ),
            (
                'House listing published before the transition and first rented after the transition',
                'Anúncio publicado antes da transição de contrato (compra de carteira) e primeiro aluguel após a transição de contrato (compra de carteira)'
            ),
            (
                'House listing published before the transition and re-rented after the transition',
                'Anúncio publicado antes da transição de contrato (compra de carteira) e realugado após a transição de contrato (compra de carteira)'
            ),
            (
                'This house has already been purchased',
                'Este imóvel já foi adquirido (compra de carteira anterior)'
            ),
            (
                'Similar house was terminated, is unpublished and has not generated a relisting, but the owner is the same',
                'Imóvel similar rescindido, despublicado, sem republicação, mesmo proprietário'
            ),
            (
                'Similar house was terminated, is unpublished, has not generated a relisting and the owner is different',
                'Imóvel similar rescindido, despublicado, sem republicação, proprietário diferente'
            ),
            (
                'House listing published after the transition',
                'Anúncio publicado após a transição de contrato (compra de carteira)'
            ),
            (
                'House is an ongoing-listing in Belo Horizonte, Rio de Janeiro or RMSP',
                'Anúncio em andamento (ongoing-listing) em Belo Horizonte, Rio de Janeiro ou RMSP'
            ),
            (
                'House is an ongoing-listing outside Belo Horizonte, Rio de Janeiro or RMSP',
                'Anúncio em andamento (ongoing-listing) fora de Belo Horizonte, Rio de Janeiro e RMSP'
            ),
            ('House is an ongoing-rentals', 'Contrato em andamento (ongoing-rentals)'),
            (
                'House is not eligible to acquire because it is a hybrid house converted by a non-CIQ channel',
                'Não elegível: híbrido convertido por canal não-CIQ'
            ),
            (
                'House is a hybrid house converted by a CIQ channel',
                'Híbrido convertido por canal CIQ'
            )
                AS t(reason_en, reason_pt)
),
fact_base AS (
    SELECT
        clp.id_listing_purchase AS sk_listing_purchase,
        lpp.id_listing_duplicity AS sk_listing_duplicity,
        clp.id_house AS sk_house,
        clp.id_house_listing AS sk_house_listing,
        lpp.id_previous_listing_paid AS sk_previous_listing_paid,
        lpp.id_similar_house_paid AS sk_similar_house_paid,
        clp.id_contract AS sk_contract,
        clp.id_accounting_entry AS sk_accounting_entry,
        clp.id_partner AS sk_partner,
        clp.id_ciq_user AS sk_user,
        clp.id_enrollment AS sk_enrollment,
        clp.id_owner AS sk_owner,
        clp.id_address_parsed_duplicity AS sk_address_parsed_duplicity,
        clp.id_atlas_duplicity AS sk_atlas_duplicity,
        clp.city_name,
        clp.city_group,
        clp.supply_source,
        clp.listing_status,
        clp.listing_category,
        clp.contract_status,
        lpp.payment_status,
        lpp.pricing_type,
        lpp.pricing_type_reason,
        lpp.acquisition_type,
        lpp.acquisition_type_reason,
        TRIM(lpp.pricing_type_reason) AS pricing_en,
        TRIM(lpp.acquisition_type_reason) AS acquisition_en,
        COALESCE(rpm.reason_pt, NULLIF(TRIM(lpp.pricing_type_reason), '')) AS pricing_pt,
        COALESCE(ram.reason_pt, NULLIF(TRIM(lpp.acquisition_type_reason), '')) AS acquisition_pt,
        CASE
            WHEN plf.is_ccv_after_post_july_rent_cs
                THEN 'ccv_after_post_july_rent_cs'
            WHEN plf.is_relisting_without_contract_90d
                THEN 'relisting_without_contract_90d'
        END AS portfolio_loss_reason,
        lpp.purchase_value,
        clp.amount_paid,
        clp.total_days_since_house_inactived,
        clp.total_days_since_publish,
        clp.has_similiar_house_by_address_parsed,
        clp.has_similiar_house_by_atlas,
        clp.has_republication,
        clp.is_first_contract_signed_by_house,
        clp.is_last_house_listing,
        clp.is_house_inactive,
        COALESCE(
            plf.is_relisting_without_contract_90d
            OR plf.is_ccv_after_post_july_rent_cs,
            FALSE
        ) AS is_portfolio_loss,
        lpp.is_eligible,
        clp.is_paid,
        clp.dt_paid,
        clp.ts_contract_signed,
        clp.ts_next_contract_signed,
        clp.ts_previous_contract_signed,
        clp.ts_publicated,
        clp.ts_house_inactived,
        clp.ts_house_registration,
        clp.ts_first_listing,
        clp.year,
        clp.month,
        clp.day
    FROM
        datalake_ciq.ciq_listing_purchase AS clp
    JOIN
        datalake_ciq.listing_purchase_pricing AS lpp
            ON lpp.id_listing_purchase = clp.id_listing_purchase
    JOIN
        portfolio_loss_flags AS plf
            ON plf.id_listing_purchase = clp.id_listing_purchase
    LEFT JOIN
        partner_reason_map AS rpm
            ON rpm.reason_en = TRIM(lpp.pricing_type_reason)
    LEFT JOIN
        partner_reason_map AS ram
            ON ram.reason_en = TRIM(lpp.acquisition_type_reason)
)
SELECT
    sk_listing_purchase,
    sk_listing_duplicity,
    sk_house,
    sk_house_listing,
    sk_previous_listing_paid,
    sk_similar_house_paid,
    sk_contract,
    sk_accounting_entry,
    sk_partner,
    sk_user,
    sk_enrollment,
    sk_owner,
    sk_address_parsed_duplicity,
    sk_atlas_duplicity,
    city_name,
    city_group,
    supply_source,
    listing_status,
    listing_category,
    contract_status,
    payment_status,
    pricing_type,
    pricing_type_reason,
    acquisition_type,
    acquisition_type_reason,
    CASE
        WHEN pricing_pt IS NULL AND acquisition_pt IS NULL
            THEN NULL
        WHEN acquisition_pt IS NULL OR pricing_en = acquisition_en
            THEN pricing_pt
        WHEN pricing_pt IS NULL
            THEN acquisition_pt
        ELSE CONCAT(pricing_pt, ' (aquisição: ', acquisition_pt, ')')
    END AS partner_justification_pt,
    portfolio_loss_reason,
    purchase_value,
    amount_paid,
    total_days_since_house_inactived,
    total_days_since_publish,
    has_similiar_house_by_address_parsed,
    has_similiar_house_by_atlas,
    has_republication,
    is_first_contract_signed_by_house,
    is_last_house_listing,
    is_house_inactive,
    is_portfolio_loss,
    is_eligible,
    is_paid,
    dt_paid,
    ts_contract_signed,
    ts_next_contract_signed,
    ts_previous_contract_signed,
    ts_publicated,
    ts_house_inactived,
    ts_house_registration,
    ts_first_listing,
    NOW() AS ts_load,
    year,
    month,
    day
FROM
    fact_base
