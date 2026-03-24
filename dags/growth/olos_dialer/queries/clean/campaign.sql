SELECT
    CampaignId AS id_campaign,
    CampaignTypeId AS id_campaign_type,
    DispositionPlanId AS id_customer,
    Description AS description,
    CampaignCode AS campaign_code,
    BillingCode AS billing_code,
    Activated AS is_activated,
    year,
    month,
    day
FROM
    datalake_olos_dialer_raw.Campaign
WHERE
    MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')