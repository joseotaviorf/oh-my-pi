SELECT
    house_id AS id_house,
    covered_amount,
    is_consenting,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_repairs_raw.instant_approval_preference