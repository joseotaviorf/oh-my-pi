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
            AND CAST(FROM_UTC_TIMESTAMP(clp.ts_contract_signed, 'America/Sao_Paulo') AS DATE) >= DATE('2026-07-01')
            AND hsa.ts_last_sale_agreement_signed IS NOT NULL
            AND hsa.ts_last_sale_agreement_signed > clp.ts_contract_signed,
            FALSE
        ) AS is_ccv_after_post_july_rent_cs
    FROM
        datalake_ciq.ciq_listing_purchase AS clp
    LEFT JOIN
        house_sale_agreement AS hsa
            ON hsa.id_house = clp.id_house
)
SELECT
    clp.id_listing_purchase AS sk_listing_purchase,
    lpp.id_listing_duplicity AS sk_listing_duplicity,
    clp.id_house AS sk_house,
    clp.id_house_listing AS sk_house_listing,
    lpp.id_previous_listing_paid AS sk_previous_listing_paid,
    lpp.id_similar_house_paid AS sk_similar_house_paid,
    clp.id_contract AS sk_contract,
    clp.id_offer AS sk_offer,
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
    clp.consultant_type,
    clp.listing_status,
    clp.listing_category,
    clp.contract_status,
    lpp.payment_status,
    lpp.pricing_type,
    lpp.pricing_type_reason,
    lpp.acquisition_type,
    lpp.acquisition_type_reason,
    CONCAT(
        CASE TRIM(lpp.acquisition_type)
            WHEN 'full-price' THEN '[Preço cheio]: '
            WHEN 'not-eligible' THEN '[Não elegível]: '
            WHEN 'reduced-price' THEN '[Preço reduzido]: '
            ELSE ''
        END,
        CASE TRIM(lpp.acquisition_type_reason)
            WHEN "Don't have a contract signed yet" THEN 'Não tem contrato assinado'
            WHEN 'House is an ongoing-rentals' THEN 'Contrato em andamento (ongoing-rentals)'
            WHEN 'Contract signed before the transition' THEN 'Contrato assinado antes da transição de contrato (compra de carteira)'
            WHEN 'House is an ongoing-listing outside Belo Horizonte, Rio de Janeiro or RMSP' THEN 'Anúncio em andamento (ongoing-listing) fora de Belo Horizonte, Rio de Janeiro e RMSP'
            WHEN 'House is an ongoing-listing in Belo Horizonte, Rio de Janeiro or RMSP' THEN 'Anúncio em andamento (ongoing-listing) em Belo Horizonte, Rio de Janeiro ou RMSP'
            WHEN 'House is not eligible to acquire because it is a hybrid house converted by a non-CIQ channel' THEN 'Não elegível: híbrido convertido por canal não-CIQ'
            WHEN 'House listing published after the transition' THEN 'Anúncio publicado após a transição de contrato (compra de carteira)'
            WHEN 'House is a hybrid house converted by a CIQ channel' THEN 'Híbrido convertido por canal CIQ'
            WHEN 'This house has already been purchased' THEN 'Este imóvel já foi adquirido (compra de carteira anterior)'
            WHEN 'Another eligible contract on the same house was already selected for payment this month' THEN 'Outro contrato elegível no mesmo imóvel já foi selecionado para pagamento neste mês'
            WHEN 'No active CIQ agent attributed to the house' THEN 'Não há agente CIQ ativo atribuído ao imóvel'
            WHEN 'Similar house was terminated, is unpublished and has not generated a relisting, but the owner is the same' THEN 'Imóvel similar rescindido, despublicado, sem republicação, mesmo proprietário'
            WHEN 'Similar house was terminated, is unpublished, has not generated a relisting and the owner is different' THEN 'Imóvel similar rescindido, despublicado, sem republicação, proprietário diferente'
            ELSE ''
        END
    ) AS acquisition_type_resume_pt,
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
    clp.ts_contract_signed_local_tz,
    clp.ts_next_contract_signed,
    clp.ts_previous_contract_signed,
    clp.ts_publicated,
    clp.ts_house_inactived,
    clp.ts_house_registration,
    clp.ts_first_listing,
    clp.ts_first_listing_local_tz,
    NOW() AS ts_load,
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
