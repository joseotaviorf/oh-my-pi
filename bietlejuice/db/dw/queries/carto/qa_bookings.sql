select
	db.sk_booking,
	date_trunc('h', db.dt_scheduling) as visit_hour,
	date_part(hour,  db.dt_scheduling) as hour_of_day,
	rf.sk_house_listing,
	rf.sk_client,
	hl.house_lat,
	hl.house_lng,
	dr.sk_region,
	dr.name,
	dr.region_code,
	rf.flg_visit_completed
from fact_listing_rent_flows rf
	join dim_booking db
		on rf.sk_booking = db.sk_booking
	join  dim_region dr
		on rf.sk_region = dr.sk_region
	join dim_house_listing hl
		on rf.sk_house_listing = hl.sk_house_listing
	join dim_date dd
		on dd.sk_date = rf.sk_visit_date
		and dd.date > '2019-05-01'
