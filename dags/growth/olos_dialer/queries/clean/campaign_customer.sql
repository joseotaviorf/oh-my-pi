SELECT
    CampaignId AS id_campaign,
    CustomerId AS id_customer,
    year,
    month,
    day
FROM
    datalake_olos_dialer_raw.CampaignCustomer
WHERE
    DATE(CONCAT(year,'-',month,'-',day)) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')