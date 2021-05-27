SELECT
    id,
    experiment_id AS id_experiment,
    name,
    description,
    percentage
FROM
    datalake_sorting_hat_raw.`variant`
