select distinct
  _year,
  _month,
  _week,
  _day,
  region,
  city,
  partial,
  dense_rank() over (partition by region,
                                  city,
                                  _year,
    				                      _month,
    								              _week,
    								              _day order by house_id asc)
    	+ dense_rank() over (partition by region,
    	                                  city,
    	                                  _year,
                                        _month,
                                        _week,
                                        _day order by house_id desc)
			- 1 as _daily,
    dense_rank() over (partition by region,
                                    city,
                                    _year,
    								                _week order by house_id asc)
    	+ dense_rank() over (partition by region,
    	                                  city,
    	                                  _year,
    								                    _week order by house_id desc)
			- 1 as _weekly,
    dense_rank() over (partition by region,
                                    city,
                                    _year,
    							                  _month order by house_id asc)
    	+ dense_rank() over (partition by region,
    	                                  city,
    	                                  _year,
    									                  _month order by house_id desc)
			- 1 as _monthly,
    dense_rank() over (partition by region,
                                    city,
                                    _year order by house_id asc)
    	+ dense_rank() over (partition by region,
    	                                  city,
    	                                  _year order by house_id desc)
			- 1 as _yearly
from listings
;