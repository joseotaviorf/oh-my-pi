SELECT
    id,
    product_id AS id_product,
    offer_term_sheet_id AS id_offer_term_sheet,
    name,
    status,
    customizations,
    start_date AS dt_started,
    end_date AS dt_ended,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
    datalake_lending_raw.offer_cohort
