SELECT
    CAST(id AS BIGINT) AS id,
    location,
    contactsInfo AS contacts_info,
    version,
    CAST(createdAt AS TIMESTAMP) AS ts_created,
    CAST(updatedAt AS TIMESTAMP) AS ts_updated,
    YEAR(updatedAt) AS year,
    MONTH(updatedAt) AS month,
    DAY(updatedAt) AS day
FROM 
    datalake_jaiminho_raw.user_contacts
