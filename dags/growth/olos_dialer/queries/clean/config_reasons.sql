SELECT
    CampaignId AS id_campaign,
    ReasonId AS id_reason,
    ReasonTypeId AS id_reason_type,
    Description AS description,
    year,
    month,
    day
FROM
    datalake_olos_dialer_raw.ConfigReasons
WHERE
    MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')