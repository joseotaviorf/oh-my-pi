SELECT
    `id` AS id_partner,
    full_name,
    short_name,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
    datalake_nazare_job_cluster_raw.partner
