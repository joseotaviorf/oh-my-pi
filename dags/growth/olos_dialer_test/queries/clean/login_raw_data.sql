SELECT
    LoginRawDataID AS id_login_raw_data,
    AgentId AS id_agent,
    CampaignId AS id_campaign,
    InsertTime AS insert_time,
    StartLogin AS ts_login_started,
    EndLogin AS ts_login_ended,
    year,
    month,
    day
FROM
    datalake_olos_dialer_test_raw.LoginRawData
WHERE
    MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')