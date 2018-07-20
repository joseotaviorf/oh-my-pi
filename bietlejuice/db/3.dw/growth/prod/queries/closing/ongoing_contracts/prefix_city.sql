with all_dates as (
	select distinct
    dd.year as _year,
    dd.month as _month,
    dd.calendar_week as _week,
    dd.day as _day,
    'QuintoAndar'::varchar as region,
    coalesce(dr.city_name, '') as city,
    dense_rank() over (partition by coalesce(dr.city_name, ''),
                                    dd.year,
    																dd.month,
    																dd.calendar_week,
    																dd.day order by f.sk_contract asc)
    	+ dense_rank() over (partition by coalesce(dr.city_name, ''),
    	                                  dd.year,
    																		dd.month,
    																		dd.calendar_week,
    																		dd.day order by f.sk_contract desc)
			- 1 as daily_count,
    dense_rank() over (partition by coalesce(dr.city_name, ''),
                                    dd.year,
    																dd.calendar_week order by f.sk_contract asc)
    	+ dense_rank() over (partition by coalesce(dr.city_name, ''),
    	                                  dd.year,
    																		dd.calendar_week order by f.sk_contract desc)
			- 1 as weekly_count,
    dense_rank() over (partition by coalesce(dr.city_name, ''),
                                    dd.year,
    																dd.month order by f.sk_contract asc)
    	+ dense_rank() over (partition by coalesce(dr.city_name, ''),
    	                                  dd.year,
    																		dd.month order by f.sk_contract desc)
			- 1 as monthly_count,
    dense_rank() over (partition by coalesce(dr.city_name, ''),
                                    dd.year order by f.sk_contract asc)
    	+ dense_rank() over (partition by coalesce(dr.city_name, ''),
    	                                  dd.year order by f.sk_contract desc)
			- 1 as yearly_count
	from fact_demand f
	join dim_contract dc
		on f.sk_contract = dc.sk_contract
	join dim_date dd
		on case
			   when dc.contract_status = 'Ativo' -- old contracts might not have signature date due to paper contract
			     then true
			   else dc.dt_signature is not null
			 end
		  and dc.contract_type = 'FullService'
		  and dd."date" between dc.dt_contract_start
		                  and case
                            when dc.contract_status != 'Ativo'
                              then least(dc.dt_contract_annulment, dc.dt_contract_intended_end, current_date)
                            else current_date
                          end
		  and (case
		  		   when date_trunc('week', dd."date") = date_trunc('week', current_date)
		  		     then dc.contract_status = 'Ativo'
		  		   else dc.contract_status != 'Cancelado'
		  		 end
		  		)
	join dim_property dpr
		on f.sk_house = dpr.sk_property
	left join dim_region dr
		on dpr.regiao_id = dr.id
	where dd."date" < current_date
  order by 6, 1, 2, 3, 4
),
all_dates_last_week as (
	select 1
),
all_dates_last_month as (
	select
    dd.year as _year,
    dd.month as _month,
    'QuintoAndar'::varchar as region,
    coalesce(dr.city_name, '') as city,
    count(distinct f.sk_contract) as monthly_count
	from fact_demand f
	join dim_contract dc
		on f.sk_contract = dc.sk_contract
	join dim_date dd
		on case
			   when dc.contract_status = 'Ativo' -- old contracts might not have signature date due to paper contract
			     then true
			   else dc.dt_signature is not null
			 end
		  and dc.contract_type = 'FullService'
		  and dd."date" between dc.dt_contract_start
		                  and case
                            when dc.contract_status != 'Ativo'
                              then least(dc.dt_contract_annulment, dc.dt_contract_intended_end, current_date)
                            else current_date
                          end
		  and (case
		  		   when date_trunc('week', dd."date") = date_trunc('week', current_date)
		  		     then dc.contract_status = 'Ativo'
		  		   else dc.contract_status != 'Cancelado'
		  		 end
		  		)
	join dim_property dpr
  	on f.sk_house = dpr.sk_property
	left join dim_region dr
		on dpr.regiao_id = dr.id
	where dd."date" < current_date
		and dd.year = date_part('year', add_months(current_date, -1))
    and dd.month = date_part('month', add_months(current_date, -1))
  	and dd.day < date_part('day', current_date)
 	group by 4, 1, 2
  order by 4, 1, 2
),
all_dates_last_year as (
	select
		dd.year as _year,
		'QuintoAndar'::varchar as region,
    coalesce(dr.city_name, '') as city,
    count(distinct f.sk_contract) as yearly_count
  from fact_demand f
	join dim_contract dc
		on f.sk_contract = dc.sk_contract
	join dim_date dd
		on case
			   when dc.contract_status = 'Ativo' -- old contracts might not have signature date due to paper contract
			     then true
			   else dc.dt_signature is not null
			 end
		  and dc.contract_type = 'FullService'
		  and dd."date" between dc.dt_contract_start
		                  and case
                            when dc.contract_status != 'Ativo'
                              then least(dc.dt_contract_annulment, dc.dt_contract_intended_end, current_date)
                            else current_date
                          end
		  and (case
		  		   when date_trunc('week', dd."date") = date_trunc('week', current_date)
		  		     then dc.contract_status = 'Ativo'
		  		   else dc.contract_status != 'Cancelado'
		  		 end
		  		)
  join dim_property dpr
  	on f.sk_house = dpr.sk_property
  left join dim_region dr
  	on dpr.regiao_id = dr.id
	where dd."date" < current_date
    and dd.year = date_part('year', add_months(current_date, -12))
  		and ((dd.month = date_part('month', add_months(current_date, -12))
  		      and dd.day < date_part('day', add_months(current_date, -12)))
  		  or dd.month < date_part('month', add_months(current_date, -12))
  		  )
	group by 3, 1
	order by 3, 1
),
