WITH
campaign_last_register AS (
    SELECT
        *
    FROM
        datalake_olos_dialer_clean.campaign
    QUALIFY
        ROW_NUMBER() OVER (PARTITION BY id_campaign ORDER BY DATE(year||'-'||month||'-'||day) DESC) = 1
),
campaign_customer_last_register AS (
    SELECT
        *
    FROM
        datalake_olos_dialer_clean.campaign_customer
    QUALIFY
        ROW_NUMBER() OVER (PARTITION BY id_campaign, id_customer ORDER BY DATE(year||'-'||month||'-'||day) DESC) = 1
),
customer_last_register AS (
    SELECT
        *
    FROM
        datalake_olos_dialer_clean.customer
    QUALIFY
        ROW_NUMBER() OVER (PARTITION BY id_customer ORDER BY DATE(year||'-'||month||'-'||day) DESC) = 1
)
SELECT
    mailing.id_lead,
    campaign.description AS campaign_name,
    customer.name AS organization,
    REPLACE(SPLIT(campaign.description, "_")[0], "5ANDAR", "QUINTO_ANDAR_OUTBOUND") AS sales_company,
    mailing.phone1,
    mailing.phone2,
    mailing.phone3,
    mailing.ts_created,
    mailing.ts_imported,
    mailing.year,
    mailing.month,
    mailing.day
FROM
    datalake_olos_dialer_clean.mailing
LEFT JOIN
    campaign_last_register AS campaign
        ON campaign.id_campaign = mailing.id_campaign
LEFT JOIN
    campaign_customer_last_register AS campaign_customer
        ON campaign_customer.id_campaign = mailing.id_campaign
LEFT JOIN
    customer_last_register AS customer
        ON customer.id_customer = campaign_customer.id_customer
WHERE
    DATE(CONCAT(mailing.year, '-', mailing.month, '-', mailing.day)) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
    AND customer.name = 'Inside Sales'