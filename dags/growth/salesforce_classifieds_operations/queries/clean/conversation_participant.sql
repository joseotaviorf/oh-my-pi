SELECT
    Id AS id,
    ConversationId AS id_conversation,
    CreatedById AS id_created_by,
    LastModifiedById AS id_last_modified_by,
    ParticipantEntityId AS id_participant_entity,
    AppType AS app_type,
    Name AS name,
    ParticipantContext AS participant_context,
    ParticipantDisplayName AS participant_display_name,
    ParticipantKey AS participant_key,
    ParticipantRole AS participant_role,
    IsDeleted AS is_deleted,
    CreatedDate AS ts_created,
    JoinedTime AS ts_joined,
    LastActiveTime AS ts_last_active,
    LastModifiedDate AS ts_last_modified,
    LeftTime AS ts_left,
    CAST(LastModifiedDate AS DATE) AS dt_updated,
    YEAR(LastModifiedDate) AS year,
    MONTH(LastModifiedDate) AS month,
    DAY(LastModifiedDate) AS day
FROM
    datalake_salesforce_classifieds_raw.conversationparticipant
WHERE
    MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
