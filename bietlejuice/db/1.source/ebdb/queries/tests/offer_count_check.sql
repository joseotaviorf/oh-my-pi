select sum(_count)
from (
	select count(*) as _count
	from Offer
	union all
	select count(*) as _count
	from PreProposta
) _sum
;