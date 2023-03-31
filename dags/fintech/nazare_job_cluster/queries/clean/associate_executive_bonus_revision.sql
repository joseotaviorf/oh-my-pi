SELECT
    `id` AS id_associate_executive_bonus,
    revision,
    bonus_fee AS gross_advance,
    invalidated_at AS ts_invalidated,
    created_at AS ts_created
FROM
    datalake_nazare_job_cluster_raw.associate_executive_bonus_revision
