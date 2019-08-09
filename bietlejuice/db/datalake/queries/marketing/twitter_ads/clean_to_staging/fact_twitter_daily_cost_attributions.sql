select
	sk_ad,
	id_ad,
	sk_ad_group,
	sk_campaign,
	account_id,
	sk_date,
    COALESCE(cast(plat_impressions['iOS devices'] as integer), 0) +
	    COALESCE(cast(plat_impressions['Android devices'] as integer), 0) +
	        COALESCE(cast(plat_impressions['Mobile web on other devices'] as integer), 0)
	            as mobile_impressions,
	COALESCE(cast(plat_impressions['Desktop and laptop computers'] as integer), 0) as desktop_impressions,
	COALESCE(cast(plat_impressions['Unknown'] as integer), 0) as other_impressions,
	COALESCE(cast(plat_impressions['iOS devices'] as integer), 0) +
	    COALESCE(cast(plat_impressions['Android devices'] as integer), 0) +
	        COALESCE(cast(plat_impressions['Mobile web on other devices'] as integer), 0) +
	            COALESCE(cast(plat_impressions['Desktop and laptop computers'] as integer), 0) +
	                COALESCE(cast(plat_impressions['Unknown'] as integer), 0)
	                    as total_impressions,
	COALESCE(cast(plat_cost['iOS devices'] as decimal(12, 2)), 0) +
	    COALESCE(cast(plat_cost['Android devices'] as decimal(12, 2)), 0) +
	        COALESCE(cast(plat_cost['Mobile web on other devices'] as decimal(12, 2)), 0)
	            as mobile_cost,
	COALESCE(cast(plat_cost['Desktop and laptop computers'] as decimal(12, 2)), 0) as desktop_cost,
	COALESCE(cast(plat_cost['Unknown'] as decimal(12, 2)), 0) as other_cost,
	COALESCE(cast(plat_cost['iOS devices'] as decimal(12, 2)), 0) +
	    COALESCE(cast(plat_cost['Android devices'] as decimal(12, 2)), 0) +
	        COALESCE(cast(plat_cost['Mobile web on other devices'] as decimal(12, 2)), 0) +
	            COALESCE(cast(plat_cost['Desktop and laptop computers'] as decimal(12, 2)), 0) +
	                COALESCE(cast(plat_cost['Unknown'] as decimal(12, 2)), 0)
	                    as total_cost,
	ts_load
from (
 SELECT
	stats.id_ad as sk_ad,
	stats.id_ad,
	adgroups.id as sk_ad_group,
	cam.id_account as account_id,
	cam.id as sk_campaign,
	cast(date_format(cast(stats.dt_created as date), '%Y%m%d') as integer) as sk_date,
	current_timestamp as ts_load,
    map_agg(stats.platform_name, stats.impressions) plat_impressions,
    map_agg(stats.platform_name, stats.cost) plat_cost
 FROM datalake_clean.marketing_twitter_ads_stats as stats
	join datalake_clean.marketing_twitter_ads as ads
	    on stats.id_ad = ads.id
	join datalake_clean.marketing_twitter_ad_groups as adgroups
		on adgroups.id = ads.id_line_item
	join datalake_clean.marketing_twitter_campaigns as cam
		on cam.id = adgroups.id_campaign
 GROUP BY 1,2,3,4,5,6,7
)