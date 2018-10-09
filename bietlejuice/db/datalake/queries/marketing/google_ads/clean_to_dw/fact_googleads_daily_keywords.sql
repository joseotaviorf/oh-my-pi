with devices_latest as (
	with t1 as (
		SELECT *,
			RANK() OVER (PARTITION BY day, keywordid
	                    	ORDER BY _sdc_report_datetime DESC)
		FROM stitch.googleads_click_performance_report
		ORDER BY day ASC
	)
	SELECT * FROM t1
	WHERE rank = 1
),
computer_devices as(
    SELECT campaignid,
     adgroupid,
     keywordid,
     device,
     day,
     SUM(clicks) as total_clicks
    FROM devices_latest
    WHERE device = 'Computers'
    GROUP BY 1,2,3,4,5
),
mobile_devices as(
    SELECT campaignid,
     adgroupid,
     keywordid,
     device,
     day,
     SUM(clicks) as total_clicks
    FROM devices_latest
    WHERE device = 'Mobile devices with full browsers'
    GROUP BY 1,2,3,4,5
),
tablet_devices as (
    SELECT campaignid,
     adgroupid,
     keywordid,
     device,
     day,
     SUM(clicks) as total_clicks
    FROM devices_latest
    WHERE device = 'Tablets with full browsers'
    GROUP BY 1,2,3,4,5
),
latest_data as (
    SELECT keywords.keywordid as sk_keyword,
      keywords.account as account_name,
      keywords.campaign as campaign_name,
      keywords.adgroup as adgroup_name,
      keywords.keyword as keyword_name,
      keywords.matchtype as match_type,
      (cast(keywords.cost as FLOAT) / 1000000) as total_cost,
      computer_devices.total_clicks as computer_clicks,
      mobile_devices.total_clicks as mobile_clicks,
      tablet_devices.total_clicks as tablet_clicks,
      (mobile_devices.total_clicks + tablet_devices.total_clicks + computer_devices.total_clicks) as sum_clicks,
      keywords.clicks as total_clicks,
      to_char(keywords.day::date, 'YYYYMMDD')::int as sk_date,
    RANK() OVER (PARTITION BY keywords.day, keywords.keywordid
                 ORDER BY keywords._sdc_report_datetime DESC)
    FROM stitch.googleads_keywords_performance_report keywords
    LEFT JOIN computer_devices
        ON computer_devices.campaignid = keywords.campaignid
            AND computer_devices.keywordid = keywords.keywordid
            AND computer_devices.day = keywords.day
    LEFT JOIN mobile_devices
        ON mobile_devices.campaignid = keywords.campaignid
            AND mobile_devices.keywordid = keywords.keywordid
            AND mobile_devices.day = keywords.day
    LEFT JOIN tablet_devices
        ON tablet_devices.campaignid = keywords.campaignid
            AND tablet_devices.keywordid = keywords.keywordid
            AND tablet_devices.day = keywords.day
    WHERE keywords.dt = '{}'
    ORDER BY keywords.day ASC
)
SELECT * FROM latest_data
WHERE rank = 1