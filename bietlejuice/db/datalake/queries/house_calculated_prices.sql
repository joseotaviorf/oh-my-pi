select
	cast(trim(p.sk_house_listing) as bigint) as sk_house_listing,
	cast(min as double) as min,
	cast(max as double) as max,
	cast(estimated as double) as estimated
from
	datalake_raw.local_price_predictor lp
join
	datalake_clean.ods_dim_house_listing p
	on cast(trim(p.id) as bigint) = lp.id
where known=1
and out=0