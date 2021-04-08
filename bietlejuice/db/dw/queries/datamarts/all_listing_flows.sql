WITH all_listings AS (
SELECT 
	f.sk_house_listing,
	f.status_history,
	CASE WHEN status_history NOT IN ('alugado', 'despublicado', 'suspenso', 'publicado') THEN 'outros'
        ELSE status_history END status_history_v2,
	case
        	when status_history = 'despublicado' and (lower(status_change_reason) like '%rescisao%' or lower(status_change_reason) like '%rescisão%') then 'ended_rental'
	     	when status_history = 'despublicado' and (lower(status_change_reason) like '%contato%'
	     		or lower(status_change_reason) like '%não atende%')then 'no_contact'
	     	when status_history = 'despublicado' and lower(status_change_reason) like '%vend%' then 'sale'
		    when status_history = 'despublicado' and (lower(status_change_reason) like '%modelo de negócio%'
		    	or lower(status_change_reason) like '%administração%')then 'business_model'
		    when status_history = 'despublicado' and lower(status_change_reason) like '%gestão%' then 'consequence_mngmt'
          	when status_history = 'despublicado' and (lower(status_change_reason) like '%locou%'
          		or lower(status_change_reason) like '%alugou%') then 'rented_elsewhere'
          	when status_history = 'suspenso' and lower(status_change_reason) like '%reservado%' then 'reservation'
	     	when status_history = 'suspenso' and lower(status_change_reason) like '%minuta%' then 'minuta'
		    when status_history = 'suspenso' and lower(status_change_reason) like '%pelo proprietário%' then 'by_owner'
		    when status_history = 'suspenso' and lower(status_change_reason) like '%gestão%' then 'consequence_mngmt'
            when (lower(status_change_reason) like '%reserv%' or lower(status_change_reason) like '%negocia%'
                or lower(status_change_reason) like '%proposta%') then 'suspended_in_negotiation'
            else null
    	END status_change_reason,
    CASE WHEN datediff('day',f.ts_status_start, COALESCE(f.ts_status_end,CURRENT_DATE)) < 14 THEN '< 2w' ELSE '>= 2w' END AS time_in_status,
    DATE(f.ts_status_start) AS dt_status_start,
	DATE(COALESCE(f.ts_status_end,CURRENT_DATE)) AS dt_status_end,
    f.ts_status_start
FROM fact_house_listing_status f
join dim_house_listing dhl
  ON dhl.sk_house_listing = f.sk_house_listing
 where dhl.version > 0
), all_listings_date AS (
SELECT DISTINCT
    al.sk_house_listing,
    al.status_history_v2,
    al.status_change_reason,
    al.time_in_status,
    d.week_start,
    al.ts_status_start,
	max(al.ts_status_start) OVER(PARTITION BY al.sk_house_listing, d.week_start) AS last_status_start
FROM dim_date d
join all_listings al
   ON d.date >= al.dt_status_start AND d.date < al.dt_status_end
WHERE d.week_start < DATE_TRUNC('week', CURRENT_DATE) + interval '1 week'
), al_week AS (
SELECT
    aldr.sk_house_listing,
    aldr.status_history_v2 AS status_history,
    aldr.status_change_reason,
    aldr.time_in_status,
	aldr.week_start,
    DATE(aldr.week_start + INTERVAL '1 week') AS next_week_start
FROM all_listings_date aldr
WHERE last_status_start = ts_status_start
), al_week_status AS (
SELECT
    COALESCE(alw_ws.sk_house_listing, alw_nws.sk_house_listing) AS sk_house_listing,
    alw_ws.status_history AS status_week_start,
    alw_nws.status_history AS status_next_week,
    alw_nws.status_change_reason as next_status_change_reason,
    CASE WHEN alw_ws.status_history IN ('despublicado', 'suspenso') then alw_ws.time_in_status END AS time_in_status,
	DATE(COALESCE(alw_ws.week_start,(COALESCE(alw_ws.next_week_start, alw_nws.week_start) - INTERVAL '1 week'))) AS week_start,
    COALESCE(alw_ws.next_week_start, alw_nws.week_start) AS next_week_start
FROM al_week alw_ws
FULL OUTER JOIN al_week alw_nws
  ON alw_ws.sk_house_listing = alw_nws.sk_house_listing AND alw_ws.next_week_start = alw_nws.week_start
), al_week_status_region AS (
SELECT
    alw.sk_house_listing,
    dr.city_group,
    alw.status_week_start,
    alw.status_next_week,
    alw.next_status_change_reason,
    alw.time_in_status,
    alw.week_start,
    alw.next_week_start
FROM al_week_status alw
LEFT JOIN fact_house_listings fhl
  ON alw.sk_house_listing = fhl.sk_house_listing
LEFT JOIN dim_region dr
  ON fhl.sk_region = dr.sk_region
WHERE dr.city_group IS NOT NULL 
)
SELECT
    week_start,
    next_week_start,
    status_week_start,
    status_next_week,
    city_group,
    time_in_status,
    COUNT(DISTINCT sk_house_listing) AS total_listings,
    COUNT(DISTINCT CASE WHEN next_status_change_reason = 'ended_rental' THEN sk_house_listing END) AS ended_rental,
    COUNT(DISTINCT CASE WHEN next_status_change_reason = 'no_contact' THEN sk_house_listing END) AS no_contact,
    COUNT(DISTINCT CASE WHEN next_status_change_reason = 'sale' THEN sk_house_listing END) AS sale,
    COUNT(DISTINCT CASE WHEN next_status_change_reason = 'business_model' THEN sk_house_listing END) AS business_model,
    COUNT(DISTINCT CASE WHEN next_status_change_reason = 'consequence_mngmt' THEN sk_house_listing END) AS consequence_mngmt,
    COUNT(DISTINCT CASE WHEN next_status_change_reason = 'rented_elsewhere' THEN sk_house_listing END) AS rented_elsewhere,
    COUNT(DISTINCT CASE WHEN next_status_change_reason = 'reservation' THEN sk_house_listing END) AS reservation,
    COUNT(DISTINCT CASE WHEN next_status_change_reason = 'minuta' THEN sk_house_listing END) AS minuta,
    COUNT(DISTINCT CASE WHEN next_status_change_reason = 'by_owner' THEN sk_house_listing END) AS by_owner,
    COUNT(DISTINCT CASE WHEN next_status_change_reason = 'suspended_in_negotiation' THEN sk_house_listing END) AS suspended_in_negotiation,
    COUNT(DISTINCT CASE WHEN next_status_change_reason IS null THEN sk_house_listing END) AS other_status_change_reason
FROM al_week_status_region alw
WHERE week_start < DATE_TRUNC('week',CURRENT_DATE) - INTERVAL '1 week' AND week_start >= '2019-07-01'
GROUP BY week_start, city_group, status_week_start, status_next_week, next_week_start, time_in_status;
