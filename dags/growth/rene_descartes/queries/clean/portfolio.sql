SELECT
    id,
    external_app_id AS id_external_app,
    portfolio_type,
    identifier_key,
    identifier_value,
    identifier_anonymized,
    external_app_name,
    created_at AS ts_created,
    updated_at AS ts_updated,
    YEAR(updated_at) AS year,
    MONTH(updated_at) AS month,
    DAY(updated_at) as day
FROM
    datalake_rene_descartes_raw.portfolio
