SELECT
    company_uuid AS uuid_company,
    listing_original_id AS id_listing_original,
    synthetic_house_id AS id_synthetic_house,
    listing_hash,
    status,
    text2filter_prediction,
    cached_location,
    CAST(last_update_date AS TIMESTAMP) AS ts_last_update,
    CAST(reviewed_at AS TIMESTAMP) AS ts_reviewed,
    CAST(created_at AS TIMESTAMP) AS ts_created,
    CAST(updated_at AS TIMESTAMP) AS ts_updated,
    YEAR(CAST(updated_at AS TIMESTAMP)) AS year,
    MONTH(CAST(updated_at AS TIMESTAMP)) AS month,
    DAY(CAST(updated_at AS TIMESTAMP)) AS day
FROM
    datalake_alias_raw.listing_fingerprint