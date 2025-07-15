SELECT
    CAST(id AS BIGINT) AS id,
    CAST(external_id AS STRING) AS id_external,
    CAST(data_controller_id AS BIGINT) AS id_data_controller,
    CAST(data_subject_category_id AS BIGINT) AS id_data_subject_category,
    purpose_acceptances,
    CAST(version AS INT) AS version,
    CAST(deleted AS BOOLEAN) AS is_deleted,
    CAST(onetrust_migrated AS BOOLEAN) AS is_onetrust_migrated,
    CAST(updated_at AS TIMESTAMP) AS ts_updated_at,
    CAST(created_at AS TIMESTAMP) AS ts_created_at,
    YEAR(CAST(updated_at AS TIMESTAMP)) AS year,
    MONTH(CAST(updated_at AS TIMESTAMP)) AS month,
    DAY(CAST(updated_at AS TIMESTAMP)) AS day
FROM datalake_privacy_hub_raw.data_subject
