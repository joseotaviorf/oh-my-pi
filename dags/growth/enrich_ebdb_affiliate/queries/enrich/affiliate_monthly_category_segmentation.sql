WITH conditional_inactives_new AS (
    SELECT
        id_date,
        id_user,
        id_user_affiliate,
        CASE
            WHEN rt.lifetime_days_cohort >= 0 
                AND rt.lifetime_days_cohort < 10 THEN 'new user'
            WHEN rt.lifetime_days_cohort < 0 THEN 'different cohort'
            WHEN rt.prospects_last_90_days = 0 THEN
                CASE WHEN rt.leads = 0 THEN 'curioso'
                     WHEN rt.listings = 0 THEN 'desconfiado'
                     WHEN rt.conversion_prospect_to_listing > 0.10 THEN 'ex-show'
                     WHEN rt.conversion_prospect_to_listing > 0.01 THEN 'ex-ok'
                     WHEN rt.conversion_prospect_to_listing < 0.01
                        AND rt.conversion_prospect_to_listing > 0 THEN 'ex-perdido'
                     ELSE 'active' 
                END
            ELSE 'active'
        END AS new_inactive,
        prospects_last_90_months_active,
        prospects_listings_last_90,
        is_last_segmentation
    FROM 
        affiliate_monthly_metrics AS rt
),
horizontal_vertical_axis AS (
    SELECT
        id_date,
        id_user_affiliate,
        id_user,
        CASE
            WHEN new_inactive = 'active' THEN
                CASE WHEN prospects_last_90_months_active >= 100 THEN 3
                     WHEN prospects_last_90_months_active < 100
                        AND prospects_last_90_months_active >= 2.5 THEN 2
                     WHEN prospects_last_90_months_active < 2.5 THEN 1
                     ELSE 0 END
            ELSE 0
            END AS horizontal_axis,
        CASE
            WHEN new_inactive = 'active' THEN
                CASE WHEN prospects_listings_last_90 >= 0.10 THEN 3
                     WHEN prospects_listings_last_90 < 0.10
                        AND prospects_listings_last_90 >= 0.01 THEN 2
                     WHEN prospects_listings_last_90 < 0.01 THEN 1
                     ELSE 0 END
            ELSE 0
            END AS vertical_axis,
        new_inactive,
        is_last_segmentation
    FROM 
        conditional_inactives_new
),
full_segmentation AS (
    SELECT
        id_date,
        id_user_affiliate,
        id_user,
        -- Next step: Create a dynamic and more self service process to manage current and new segmentation names
        CASE
            WHEN new_inactive <> 'active' THEN new_inactive
            WHEN horizontal_axis = 1 
                AND vertical_axis = 1 THEN 'teste'
            WHEN horizontal_axis = 1 
                AND vertical_axis = 2 THEN 'fantasma'
            WHEN horizontal_axis = 1 
                AND vertical_axis = 3 THEN 'certeiro'
            WHEN horizontal_axis = 2 
                AND vertical_axis = 1 THEN 'perdido'
            WHEN horizontal_axis = 2 
                AND vertical_axis = 2 THEN 'captador'
            WHEN horizontal_axis = 2 
                AND vertical_axis = 3 THEN 'corretor'
            WHEN horizontal_axis = 3 
                AND vertical_axis = 1 THEN 'volume-erro'
            WHEN horizontal_axis = 3 
                AND vertical_axis = 2 THEN 'volume-ok'
            WHEN horizontal_axis = 3 
                AND vertical_axis = 3 THEN 'estrela'
            ELSE 'sem-segmentacao'
        END AS segmentation,
        is_last_segmentation
    FROM 
        horizontal_vertical_axis
)
SELECT
    id_date,
    id_user_affiliate,
    id_user,
    segmentation,
    is_last_segmentation
FROM 
    full_segmentation