SELECT
id_ad,
segment_name,
segment_value,
(
	coalesce(cast(all_on_twitter_impressions[1] AS integer), 0) +
	coalesce(cast(publisher_network_segment_impressions[1] AS integer), 0)
) AS all_impressions,
(
	coalesce(cast(all_on_twitter_engagements[1] AS integer), 0) +
	coalesce(cast(publisher_network_segment_engagements[1] AS integer), 0)
) AS all_engagements,
(
	coalesce(cast(all_on_twitter_billed_charge_local_micro[1] AS bigint), 0) +
	coalesce(cast(publisher_network_segment_billed_charge_local_micro[1] AS bigint), 0)
)/1000000 AS all_billed_charge_local_micro,
(
	coalesce(cast(all_on_twitter_billed_engagements[1] AS integer), 0) +
	coalesce(cast(publisher_network_segment_billed_engagements[1] AS integer), 0)
) AS all_billed_engagements,
(
	coalesce(cast(all_on_twitter_clicks[1] AS integer), 0) +
	coalesce(cast(publisher_network_segment_clicks[1] AS integer), 0)
) AS all_clicks,
(
	coalesce(cast(all_on_twitter_url_clicks[1] AS integer), 0) +
	coalesce(cast(publisher_network_segment_url_clicks[1] AS integer), 0)
) AS all_url_clicks
FROM datalake_raw.marketing_twitter_ads_stats
where dt='{date}' and acc='{account}'