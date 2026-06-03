SELECT
    CampaignId AS id_campaign,
    TableName AS table_name,
    year,
    month,
    day
FROM
    datalake_olos_dialer_test_raw.MailingInformation
WHERE
    MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')