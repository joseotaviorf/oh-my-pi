SELECT
    rc.category_level AS id_guarantee_category,
    rc.id AS id_risk_category,
    rc.guarantee_factor,
    rc.deposit_factor,
    NULLIF(rc.category_description, '') AS category_description,
    rc.is_guarantee_allowed,
    rc.is_deposit_allowed,
    rc.ts_created AS ts_guarantee_category_created,
    rc.ts_updated AS ts_guarantee_category_updated,
    NOW() AS ts_load
FROM
  datalake_rental_guarantee_clean.risk_category AS rc