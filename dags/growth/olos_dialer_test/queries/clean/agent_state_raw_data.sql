SELECT
    AgentId AS id_agent,
    AgentStateRawDataID AS id_agent_state_raw_data,
    CallId AS id_call,
    CallIdTelecom AS id_call_telecom,
    CampaignId AS id_campaign,
    AgentStatus AS agent_status,
    Reason AS reason,
    InsertTime AS insert_time,
    StartState AS ts_state_started,
    EndState AS ts_state_ended,
    year,
    month,
    day
FROM
    datalake_olos_dialer_test_raw.AgentStateRawData
WHERE
    MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')