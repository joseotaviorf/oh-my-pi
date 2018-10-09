-- CREATE GOOGLE ADS CAMPAIGN DIMENSION TABLE
WITH latest as (
    SELECT
        campaignid as sk_campaign,
        campaign as campaign_name,
        labels,
        advertisingchannel as advertising_channel_type,
        RANK() OVER (PARTITION BY day, campaignid
                        ORDER BY _sdc_report_datetime DESC)
    FROM datalake_raw.marketing_googleads_campaigns campaign
    WHERE campaign.created_dt = '{dt}'
    GROUP BY 1, 2, 3, 4, day, _sdc_report_datetime
    ORDER BY day ASC
)
SELECT * FROM latest
WHERE rank = 1