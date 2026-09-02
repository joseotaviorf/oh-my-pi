SELECT
    Id AS id,
    CreatedById AS id_created_by,
    LastModifiedById AS id_last_modified_by,
    ParticipantAppType AS participant_app_type,
    ParticipantRole AS participant_role,
    ParticipantSubject AS participant_subject,
    IsDeleted AS is_deleted,
    CreatedDate AS ts_created,
    LastModifiedDate AS ts_last_modified,
    SystemModstamp AS ts_system_mod,
    CAST(LastModifiedDate AS DATE) AS dt_updated,
    YEAR(LastModifiedDate) AS year,
    MONTH(LastModifiedDate) AS month,
    DAY(LastModifiedDate) AS day
FROM
    datalake_salesforce_classifieds_raw.participant
WHERE
    MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
