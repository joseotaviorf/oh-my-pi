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
),
previous_listing_paid AS (
    SELECT
        listing.id_house,
        listing.id_house_listing,
        listing_paid.id_listing_purchase AS id_previous_listing_paid,
        ROW_NUMBER() OVER (PARTITION BY listing.id_house ORDER BY listing_paid.is_paid DESC) = 1 AS is_last_listing_paid
    FROM
        datalake_ciq.ciq_listing_purchase AS listing
    JOIN
        datalake_ciq.ciq_listing_purchase AS listing_paid
            ON listing_paid.id_house = listing.id_house
            AND listing_paid.id_house_listing <> listing.id_house_listing
            AND listing_paid.is_paid IS TRUE
),
purchase_pricing AS (
    SELECT
        clp.id_listing_purchase,
        lpe.id_listing_duplicity,
        clp.id_house,
        clp.id_house_listing,
        lpe.id_similar_house AS id_similar_house_paid,
        plp.id_previous_listing_paid,
        CASE
            WHEN plp.id_previous_listing_paid IS NOT NULL THEN 'not-eligible: This house has already been purchased'
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
            WHEN clp.initial_pricing_type = 'new-listings' THEN 'full-price: House listing published after the transition'
            WHEN clp.initial_pricing_type = 'not-eligible' THEN clp.initial_pricing_type_reason
            WHEN clp.initial_pricing_type = 'ongoing-listings'
                AND (
                    clp.city_group IN ('belo horizonte', 'rio de janeiro')
                    OR clp.city_group = 'rmsp'
                )
                THEN 'reduced-price: House is an ongoing-listing in Belo Horizonte, Rio de Janeiro or RMSP'
            WHEN clp.initial_pricing_type = 'ongoing-listings' THEN 'full-price: House is an ongoing-listing outside Belo Horizonte, Rio de Janeiro or RMSP'
            WHEN clp.initial_pricing_type = 'ongoing-rentals' THEN 'reduced-price: House is an ongoing-rentals'
            WHEN clp.initial_pricing_type = 'hybrid' AND clp.supply_source <> "CIQ" THEN 'reduced-price: House is not eligible to acquire because it is a hybrid house converted by a non-CIQ channel'
            WHEN clp.initial_pricing_type = 'hybrid' AND clp.supply_source = "CIQ" THEN 'full-price: House is a hybrid house converted by a CIQ channel'
        END AS acquisition_type_reason,
        COALESCE(SPLIT(acquisition_type_reason, ':')[0], 'full-price') AS acquisition_type,
        CASE
            WHEN acquisition_type = 'not-eligible' THEN 0
            WHEN acquisition_type = 'reduced-price' THEN 150
            WHEN acquisition_type = 'full-price' THEN 1000
        END AS purchase_value,
        CASE
            WHEN acquisition_type = 'not-eligible' THEN 'not-eligible'
            WHEN clp.is_paid IS TRUE THEN 'paid'
            ELSE 'pending'
        END AS payment_status,
        CASE
            WHEN acquisition_type = 'not-eligible' AND clp.initial_pricing_type <> 'not-eligible' THEN acquisition_type_reason
            ELSE clp.initial_pricing_type_reason
        END AS pricing_type_reason,
        CASE
            WHEN acquisition_type = 'not-eligible' AND clp.initial_pricing_type <> 'not-eligible' THEN acquisition_type
            ELSE clp.initial_pricing_type
        END AS pricing_type,
        NOW() AS ts_load
    FROM
        datalake_ciq.ciq_listing_purchase AS clp
    LEFT JOIN
        listing_purchase_duplicity AS lpe
            ON lpe.id_listing_purchase = clp.id_listing_purchase
            AND lpe.is_last_similiar_house_paid IS TRUE
    LEFT JOIN
        previous_listing_paid AS plp
            ON plp.id_house = clp.id_house
            AND plp.id_house_listing = clp.id_house_listing
            AND plp.is_last_listing_paid IS TRUE
    WHERE
        clp.business_context = 'RENT'
        AND clp.consultant_type = 'CIQ_FULL'
)
SELECT 
    ppp.id_listing_purchase,
    ppp.id_listing_duplicity,
    ppp.id_house,
    ppp.id_house_listing,
    ppp.id_similar_house_paid,
    ppp.id_previous_listing_paid,
    ppp.pricing_type,
    TRIM(SPLIT(ppp.pricing_type_reason, ':')[1]) AS pricing_type_reason,
    ppp.acquisition_type,
    TRIM(SPLIT(ppp.acquisition_type_reason, ':')[1]) AS acquisition_type_reason,
    COALESCE(ppp.pricing_type, 'not-eligible') <> 'not-eligible' AS is_eligible,
    ppp.purchase_value,
    ppp.payment_status,
    ppp.ts_load
FROM 
    purchase_pricing AS ppp
GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14
