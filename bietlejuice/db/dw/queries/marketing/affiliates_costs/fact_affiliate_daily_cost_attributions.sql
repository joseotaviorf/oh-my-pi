with affiliate_manual_costs as (
	select
		cast(to_char(to_date(gh.date, 'YYYY-MM-DD'), 'YYYYMMDD') as integer) as sk_date,
		coalesce(city_group, 'Not Mapped') as city_group,
		coalesce(mkt_origin, 'Not Mapped') as mkt_origin,
		sum(
			cast(
				coalesce(
					NULLIF(
						replace(replace(promotional_bonus, 'R$', ''), ',', '')
						, '')
					, '0')
			as numeric(10,2))
			) as promotional_bonus,
		sum(
			cast(
				coalesce(
					NULLIF(
						replace(replace(notification, 'R$', ''), ',', '')
						, '')
					, '0')
			as numeric(10,2))
			) as notification,
		sum(
			cast(
				coalesce(
					NULLIF(
						replace(replace(other, 'R$', ''), ',', '')
						, '')
					, '0')
			as numeric(10,2))
			) as other
	from datalake_raw.gsheets_affiliates_manual_cost_engagement gh
	group by 1,2,3
), affiliate_eng_cost as (
select
	sk_date,
	coalesce(dr.city_group, 'Not Mapped') as city_group,
	case when affiliate_type = 'Standard' then 'Indica Aí - General'
		when affiliate_type = 'Agent' then 'Indica Aí - Agents'
		when affiliate_type = 'Doorman' then 'Doorman'
		else 'Not Mapped'
		end as mkt_origin,
	sum(case
		when commission_type = 'valorFixoPorIndicacaoDeImovel' then fa.value_brl
		else 0 end
		) as commission_listing,
	sum(case
		when commission_type = 'porcentagemPorIndicacaoDeImovel' then fa.value_brl
		else 0 end
		) as commission_rent,
	sum(case
		when commission_type in ('comissaoSobreAfiliadoIndicado', 'comissaoUnicaSobreAfiliadoIndicado') then fa.value_brl
		else 0 end
		) as commission_mgm
from marketing.fact_affiliate_daily_engagement_cost fa
left join dim_region dr on fa.sk_region = dr.sk_region
group by 1, 2, 3
), affiliate_hist as (
select
	cast(to_char(to_date(gh.date, 'YYYY-MM-DD'), 'YYYYMMDD') as integer) as sk_date,
	coalesce(city_group, 'Not Mapped') as city_group,
	coalesce(mkt_origin, 'Not Mapped') as mkt_origin,
	sum(
		cast(
			coalesce(
				NULLIF(
					replace(replace(commission_listing, 'R$', ''), ',', '')
					, '')
				, '0')
		as numeric(10,2))
		) as commission_listing,
	sum(
		cast(
			coalesce(
				NULLIF(
					replace(replace(commission_rent, 'R$', ''), ',', '')
					, '')
				, '0')
		as numeric(10,2))
		) as commission_rent,
	sum(
		cast(
			coalesce(
				NULLIF(
					replace(replace(commission_mgm, 'R$', ''), ',', '')
					, '')
				, '0')
		as numeric(10,2))
		) as commission_mgm,
	sum(
		cast(
			coalesce(
				NULLIF(
					replace(replace(notification, 'R$', ''), ',', '')
					, '')
				, '0')
		as numeric(10,2))
		) as notification,
	sum(
		cast(
			coalesce(
				NULLIF(
					replace(replace(promotional_bonus, 'R$', ''), ',', '')
					, '')
				, '0')
		as numeric(10,2))
		) as promotional_bonus,
	sum(
		cast(
			coalesce(
				NULLIF(
					replace(replace(other, 'R$', ''), ',', '')
					, '')
				, '0')
		as numeric(10,2))
		) as other
from datalake_raw.gsheets_affiliates_manual_cost_engagement_history gh
group by 1,2,3
)
	select
		coalesce(aec.sk_date, amc.sk_date) as sk_date,
		coalesce(aec.city_group, amc.city_group) as city_group,
		coalesce(aec.mkt_origin, amc.mkt_origin) as mkt_origin,
		coalesce(aec.commission_listing, 0) as commission_listing,
		coalesce(aec.commission_rent, 0) as commission_rent,
		coalesce(aec.commission_mgm, 0) as commission_mgm,
		coalesce(amc.promotional_bonus, 0) as promotional_bonus,
		coalesce(amc.notification, 0) as notification,
		coalesce(amc.other, 0) as other,
		round(coalesce(cast(tcm.rate as numeric(10,2)),0) *
		    (coalesce(aec.commission_listing, 0) +
            coalesce(aec.commission_rent, 0) +
            coalesce(aec.commission_mgm, 0) +
            coalesce(amc.promotional_bonus, 0)), 2) as commission_tradecom,
        getdate() as ts_load
	from affiliate_eng_cost aec
	full outer join affiliate_manual_costs amc
		on amc.sk_date = aec.sk_date
		and amc.city_group = aec.city_group
		and amc.mkt_origin = aec.mkt_origin
	left join datalake_raw.gsheets_affiliates_cost_tradecom_configuration tcm
	    on coalesce(aec.sk_date, amc.sk_date)
	        between cast(to_char(cast(date_from as date), 'YYYYMMDD') as integer)
	            and cast(to_char(cast(date_until as date), 'YYYYMMDD') as integer)
union
	select
		ah.sk_date,
		ah.city_group,
		ah.mkt_origin,
		ah.commission_listing,
		ah.commission_rent,
		ah.commission_mgm,
		ah.promotional_bonus,
		ah.notification,
		ah.other,
		round(coalesce(cast(tcm.rate as numeric(10,2)),0) *
            (ah.commission_listing +
            ah.commission_rent +
            ah.commission_mgm +
            ah.promotional_bonus), 2) as commission_tradecom,
        getdate() as ts_load
	from
		affiliate_hist ah
	left join datalake_raw.gsheets_affiliates_cost_tradecom_configuration tcm
	    on ah.sk_date
	        between cast(to_char(cast(date_from as date), 'YYYYMMDD') as integer)
	            and cast(to_char(cast(date_until as date), 'YYYYMMDD') as integer)
