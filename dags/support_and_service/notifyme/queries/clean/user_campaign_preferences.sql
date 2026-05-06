SELECT
    CAST(id AS BIGINT) AS id,
    CAST(user_id AS BIGINT) AS id_user,
    campaign_name,
    CAST(created_at AS TIMESTAMP) AS ts_created,
    CAST(updated_at AS TIMESTAMP) AS ts_updated,
    YEAR(updated_at) AS year,
    MONTH(updated_at) AS month,
    DAY(updated_at) AS day
FROM datalake_notifyme_raw.user_campaign_preferences
