SELECT
    CAST(id AS BIGINT) AS id,
    CAST(userId AS BIGINT) AS id_user,
    channel,
    country,
    env,
    name,
    status,
    size,
    template,
    userEmail AS user_email,
    CAST(createdAt AS TIMESTAMP) AS ts_created,
    CAST(updatedAt AS TIMESTAMP) AS ts_updated,
    CAST(sendAt AS TIMESTAMP) AS ts_sent,
    YEAR(updatedAt) AS year,
    MONTH(updatedAt) AS month,
    DAY(updatedAt) AS day
FROM datalake_jaiminho_raw.campaigns
