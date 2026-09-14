SELECT
    id,
    type,
    max_sale_value,
    max_rent_value,
    max_family_income,
    max_per_capita_income,
    enabled AS is_enabled,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
    datalake_ebdb_raw.SocialHousingProgram
