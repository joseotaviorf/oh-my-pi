with computer_device as (
  select day, keywordid, sum(cast(clicks as integer)) as sum_device
  from stitch.adwords_click_performance_report
  WHERE device = 'Computers'
  group by 1, 2
),
mobile_device as (
  select day, keywordid, sum(cast(clicks as integer)) as sum_device
  from stitch.adwords_click_performance_report
  WHERE device = 'Mobile devices with full browsers'
  group by 1, 2
),
tablet_device as (
  select day, keywordid, sum(cast(clicks as integer)) as sum_device
  from stitch.adwords_click_performance_report
  WHERE device = '	Tablets with full browsers'
  group by 1, 2
)

SELECT
  keywords.keywordid as sk_keyword,
  keywords.keyword as keyword_name,
  keywords.cost as total_cost,
  keywords.impressions,
  computer_device.sum_device as computer_device,
  tablet_device.sum_device as tablet_device,
  mobile_device.sum_device as mobile_device,
  keywords.clicks as total_clicks,
  keywords.day
FROM stitch.adwords_keywords_performance_report keywords
LEFT JOIN computer_device
  ON computer_device.keywordid = keywords.keywordid AND computer_device.day = keywords.day
LEFT JOIN tablet_device
  ON tablet_device.keywordid = keywords.keywordid AND tablet_device.day = keywords.day
LEFT JOIN mobile_device
  ON mobile_device.keywordid = keywords.keywordid AND mobile_device.day = keywords.day
WHERE keywords.account != '[deprecated] QuintoAndar - Display'
LIMIT 200