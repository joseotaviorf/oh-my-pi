SELECT
    Id AS id,
    ConversationChannelId AS id_conversation_channel,
    CreatedById AS id_created_by,
    LastModifiedById AS id_last_modified_by,
    ConversationIdentifier AS conversation_identifier,
    Name AS name,
    IsDeleted AS is_deleted,
    CreatedDate AS ts_created,
    EndTime AS ts_end,
    LastModifiedDate AS ts_last_modified,
    StartTime AS ts_start,
    CAST(LastModifiedDate AS DATE) AS dt_updated,
    YEAR(LastModifiedDate) AS year,
    MONTH(LastModifiedDate) AS month,
    DAY(LastModifiedDate) AS day
FROM
    datalake_salesforce_classifieds_raw.conversation
WHERE
    MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
