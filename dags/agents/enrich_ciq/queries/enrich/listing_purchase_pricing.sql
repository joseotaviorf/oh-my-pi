WITH listing_purchase_duplicity AS (
    SELECT 
        lpe.id_listing_duplicity,
        lpe.id_listing_purchase,
        lpe.id_similar_house,
        lpe.dt_similiar_house_contract_termination,
        lpe.has_similiar_house_republication,
        lpe.similar_house_listing_status,
        lpe.is_same_owner,
        ROW_NUMBER() OVER (PARTITION BY lpe.id_listing_purchase ORDER BY lpe.dt_similiar_house_paid DESC) = 1 AS is_last_similiar_house_paid
    FROM
        datalake_ciq.listing_purchase_duplicity AS lpe
    WHERE
        lpe.is_similiar_house_paid IS TRUE
)
SELECT DISTINCT
    clp.id_listing_purchase,
    lpe.id_listing_duplicity,
    clp.id_house,
    clp.id_house_listing,
    lpe.id_similar_house,
    clp.pricing_type,
    clp.pricing_type_reason,
    CASE
        WHEN clp.pricing_type = 'new-listings' THEN 'full-price: House listing published after the transition'
        WHEN clp.pricing_type = 'not-eligible' THEN clp.pricing_type_reason
        WHEN clp.pricing_type = 'ongoing-rentals'
            AND (
                clp.city_group IN ('belo horizonte', 'rio de janeiro')
                OR clp.city_group = 'rmsp'
            )
            THEN 'reduced-price: House is an ongoing rental in Belo Horizonte, Rio de Janeiro or RMSP'
        WHEN clp.pricing_type = 'ongoing-rentals' THEN 'full-price: House is an ongoing rental outside Belo Horizonte, Rio de Janeiro or RMSP'
        WHEN clp.pricing_type = 'ongoing-listings' THEN 'reduced-price: House is an ongoing listing'
        WHEN clp.pricing_type = 'hybrid' AND clp.supply_source <> "CIQ" THEN 'reduced-price: House is not eligible to acquire because it is a hybrid house converted by a non-CIQ channel'
        WHEN clp.pricing_type = 'hybrid' AND clp.supply_source = "CIQ" THEN 'full-price: House is a hybrid house converted by a CIQ channel'
        WHEN lpe.dt_similiar_house_contract_termination IS NOT NULL 
            AND lpe.has_similiar_house_republication IS FALSE
            AND lpe.similar_house_listing_status = "UNPUBLISHED"
            AND lpe.is_same_owner IS TRUE
            THEN 'not-eligible: Similar house was terminated, is unpublished and has not generated a relisting, but the owner is the same'
        WHEN lpe.dt_similiar_house_contract_termination IS NOT NULL 
            AND lpe.has_similiar_house_republication IS FALSE
            AND lpe.similar_house_listing_status = "UNPUBLISHED"
            AND lpe.is_same_owner IS FALSE
            THEN 'full-price: Similar house was terminated, is unpublished, has not generated a relisting and the owner is different'
    END AS acquisition_type_reason,
    COALESCE(SPLIT(acquisition_type_reason, ':')[0], 'full-price') AS acquisition_type,
    CASE
        WHEN acquisition_type = 'not-eligible' THEN 0
        WHEN acquisition_type = 'reduced-price' THEN 150
        WHEN acquisition_type = 'full-price' THEN 1000
    END AS purchase_value,
    NOW() AS ts_load
FROM
    datalake_ciq.ciq_listing_purchase AS clp
LEFT JOIN
    listing_purchase_duplicity AS lpe
        ON lpe.id_listing_purchase = clp.id_listing_purchase
        AND lpe.is_last_similiar_house_paid IS TRUE
WHERE
    clp.business_context = 'RENT'
    AND clp.consultant_type = 'CIQ_FULL'