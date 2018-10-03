SELECT
     keywords.keywordid as sk_keyword,
     keywords.keywordid as keyword_id,
     keywords.account as account_name,
     keywords.campaign as campaign_name,
     keywords.adgroup as adgroup_name,
     campaign.labels,
     campaign.advertisingchannel as advertising_channel_type
FROM stitch.adwords_keywords_performance_report keywords
JOIN stitch.adwords_campaign_performance_report campaign
    ON campaign.campaignid = keywords.campaignid
GROUP BY 1, 2, 3, 4, 5, 6, 7
LIMIT 200