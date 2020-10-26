SELECT
    CONCAT(id_campaign, '-', campaign_name) AS id,
    *
FROM
    datalake_marketing_costs_clean.criteo_campaigns
WHERE
    year={year} and month={month} and day={day}
