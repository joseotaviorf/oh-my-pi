SELECT
    id AS id_variant,
    id_experiment,
    name AS variant_name,
    description AS variant_description,
    percentage AS variant_percentage_paticipation_on_test,
    NOW() AS ts_load
FROM
    datalake_sorting_hat_clean.variant