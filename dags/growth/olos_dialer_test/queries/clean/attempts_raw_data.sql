SELECT
    AgentId AS id_agent,
    AttemptsRawDataID AS id_attempts_raw_data,
    CallId AS id_call,
    CallIdTelecom AS id_call_telecom,
    CampaignId AS id_campaign,
    BIGINT(CustomerId) AS id_lead,
    DispositionId AS id_disposition,
    MailingPhoneNumberId AS id_mailing_phone_number,
    MailingRecordId AS id_mailing_record,
    PhoneTypeId AS id_phone_type,
    Dnis AS dnis,
    OriginalPhoneNumber AS original_phone_number,
    Route AS route,
    TableName AS table_name,
    TIMESTAMP(StartDate) AS ts_started,
    TIMESTAMP(EndCall) AS ts_call_ended,
    TIMESTAMP(EndWrap) AS ts_wrap_ended,
    year,
    month,
    day
FROM
    datalake_olos_dialer_test_raw.AttemptsRawData
WHERE
    MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')