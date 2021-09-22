SELECT
    id,
    credit_evaluation_id AS id_credit_evaluation,
    user_id AS id_user,
    house_id AS id_house,
    variant_id AS id_variant,
    result,
    city,
    version,
    created_at AS ts_created,
    expiration_date AS ts_expired
FROM
    datalake_sorting_hat_raw.`earlycreditanalysis`
