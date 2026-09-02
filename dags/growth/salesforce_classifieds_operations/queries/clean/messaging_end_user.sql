SELECT
    Id AS id,
    CreatedById AS id_created_by,
    LastModifiedById AS id_last_modified_by,
    MessagingChannelId AS id_messaging_channel,
    OwnerId AS id_owner,
    CurrencyIsoCode AS currency_iso_code,
    IsoCountryCode AS iso_country_code,
    Locale AS locale,
    MessageType AS message_type,
    MessagingConsentStatus AS messaging_consent_status,
    MessagingPlatformKey AS messaging_platform_key,
    Name AS name,
    ProfilePictureUrl AS profile_picture_url,
    IsDeleted AS is_deleted,
    IsFullyOptedIn AS is_fully_opted_in,
    CreatedDate AS ts_created,
    LastModifiedDate AS ts_last_modified,
    LastReferencedDate AS ts_last_referenced,
    LastViewedDate AS ts_last_viewed,
    SystemModstamp AS ts_system_mod,
    CAST(LastModifiedDate AS DATE) AS dt_updated,
    YEAR(LastModifiedDate) AS year,
    MONTH(LastModifiedDate) AS month,
    DAY(LastModifiedDate) AS day
FROM
    datalake_salesforce_classifieds_raw.messagingenduser
WHERE
    MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
