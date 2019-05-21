with campaigns_full as (
    with google as (
	select  
		fg.sk_date,
		'google' as origin,
		'fact_google_daily_cost_attributions' as fact_cost,			
		coalesce(dgk.campaign_name, dga.campaign_name, dgc.campaign_name) as campaign_name,
		lower(SPLIT_PART(coalesce(dgk.campaign_name, dga.campaign_name, dgc.campaign_name), '.', 2)) as campaign_city,
		lower(SPLIT_PART(coalesce(dgk.campaign_name, dga.campaign_name, dgc.campaign_name), '.', 3)) as campaign_city_alternative,
		coalesce(dgk.account_name, dga.account_name, dgc.account_name) as account_name,
		lower(coalesce(dgk.campaign_name, dga.campaign_name, dgc.campaign_name)) as campaign_name_l,
		lower(coalesce(dgk.account_name, dga.account_name, dgc.account_name)) as account_name_l,
		coalesce(dgk.campaign_name, dga.campaign_name, dgc.campaign_name) as utm_campaign,
		dgk.keyword_name || '_' || lower(left(dgk.match_type, 1)) as utm_term,
		cast(dga.ad_id as varchar) as utm_content,
		fg.desktop_cost as desktop_cost,
		fg.mobile_cost as mobile_cost,
		null as other_cost,
		null as total_cost
	from marketing.fact_google_daily_cost_attributions fg
	left join marketing.dim_google_keyword dgk 
		on dgk.sk_keyword = fg.sk_keyword
	left join marketing.dim_google_ad dga 
		on dga.sk_ad = fg.sk_ad
	left join marketing.dim_google_campaign dgc 
		on dgc.sk_campaign = fg.sk_campaign
	where fg.sk_date >= 20180101
	)
	select
	    sk_date,
		origin,
		fact_cost,
		campaign_name,
		case when campaign_city ~ '^[0-9]+$' then campaign_city_alternative else campaign_city end as campaign_city,
		account_name,
		campaign_name_l,
		account_name_l,
		utm_campaign,
		utm_term,
		utm_content,
		desktop_cost,
		mobile_cost,
		other_cost,
		total_cost
	from google
UNION
    select
		ff.sk_date,
		'facebook'  as origin,
		'fact_facebook_daily_cost_attributions' as fact_cost,
		df.campaign_name,
		lower(SPLIT_PART(df.campaign_name, '.', 4)) as campaign_city,
		df.account_name,
		lower(df.campaign_name) as campaign_name_l,
		lower(df.account_name) as account_name_l,
		df.campaign_name as utm_campaign,
		df.adset_name as utm_term,
		df.ad_name as utm_content,
		ff.desktop_spend as desktop_cost,
		ff.mobile_spend as mobile_cost,
		ff.other_spend as other_cost,
		null as total_cost
	from marketing.fact_facebook_daily_cost_attributions ff
	join marketing.dim_facebook_ad df
		on ff.sk_ad = df.sk_ad
	where ff.sk_date >= 20180101
UNION
    select 
        ftc.sk_date,
        'trovit' as origin,
        'fact_trovit_daily_cost_attributions' as fact_cost,
        dtc.campaign_name,
        null as campaign_city,
        null as account_name,
        lower(dtc.campaign_name) as campaign_name_l,
        null as account_name_l, 
        null as utm_campaign, 
        null as utm_term, 
        null as utm_content, 
        ftc.desktop_cost as desktop_cost,
        ftc.mobile_cost as mobile_cost,
        null as other_cost,
        null as total_cost
    from marketing.fact_trovit_daily_cost_attributions ftc
    left join marketing.dim_trovit_campaign dtc 
    	on ftc.sk_trovit_campaign = dtc.sk_trovit_campaign
    where ftc.sk_date >= 20180101
UNION
	select 
        fct.sk_date,
        'criteo' as origin,
        'fact_criteo_daily_cost_attributions' as fact_cost,
        dct.campaign_name,
        null as campaign_city,
        null as account_name, 
        lower(dct.campaign_name) as campaign_name_l,
        null as account_name_l, 
        null as utm_campaign, 
        null as utm_term, 
        null as utm_content, 
        null as desktop_cost, 
        null as mobile_cost, 
        null as other_cost, 
        fct.cost as total_cost
	from marketing.fact_criteo_daily_cost_attributions fct
	left join marketing.dim_criteo_campaign dct 
		on fct.sk_criteo_campaign = dct.sk_criteo_campaign
	where fct.sk_date >= 20180101
UNION
    select
        frt.sk_date,
        'rtb' as origin,
        'fact_rtb_daily_cost_attributions' as fact_cost,
        drt.campaign_name,
        'rmsp' as campaign_city,
        null as account_name, 
        lower(drt.campaign_name) as campaign_name_l,
        null as account_name_l, 
        null as utm_campaign, 
        null as utm_term, 
        null as utm_content, 
        sum(coalesce(case when device = 'Desktop' then cost end, 0)) as desktop_cost, 
        sum(coalesce(case when device = 'Mobile' then cost end, 0)) as mobile_cost, 
        sum(coalesce(case when device = 'Other' then cost end, 0)) as other_cost, 
        null as total_cost
      from marketing.fact_rtb_daily_cost_attributions frt
      left join 
      	-- records in dim table are repeated
      	(select distinct * from marketing.dim_rtb_campaign) drt 
      	on frt.sk_rtb_campaign = drt.sk_rtb_campaign
      where frt.sk_date >= 20180101
      group by 1,2,3,4,5,6,7,8,9,10,11
UNION
     select 
        fcl.sk_cost_date,
        dcl.name as origin,
        'fact_daily_classifieds_costs' as fact_cost,
        null as campaign_name, 
        'rmsp' as campaign_city, 
        null as account_name, 
        null as campaign_name_l, 
        null as account_name_l, 
        null as utm_campaign,
        null as utm_term, 
        null as utm_content,
        null as desktop_cost,
        null as mobile_cost,
        null as other_cost,
        fcl.cost as total_cost
      from marketing.fact_daily_classifieds_costs fcl
      left join marketing.dim_classified dcl on fcl.sk_classified = dcl.sk_classified
      where fcl.sk_cost_date >= 20180101
)
,demand_tax as (
	select 
		cf.origin,
		cf.sk_date,
		cf.account_name,
		cf.campaign_name,
		-- city via manual mapping
		mccc.city_group as cost_city_group,
		-- city via campaign_name full name written
		case
			when cf.campaign_name_l like '%s_o_paulo%' or cf.campaign_name_l like '%sp detailed%' then 'RMSP'
			when cf.campaign_name_l like 'sp %' then 'RMSP'
			when cf.campaign_name_l like '%all cities%' then 'RMSP'
			when cf.campaign_name_l like '%rmsp%' then 'RMSP'
			when cf.campaign_name_l like '%guarulhos%' then 'RMSP'
			when cf.campaign_name_l like '%abc%' then 'RMSP'
			when cf.campaign_name_l like '%barueri%' then 'RMSP'
			when cf.campaign_name_l like '%osasco%' then 'RMSP'
			when cf.campaign_name_l like '%jundia%' then 'RMSP'
			when cf.campaign_name_l like '%santo_andr%' then 'RMSP'
			when cf.campaign_name_l like '%s_o_bernardo%' then 'RMSP'
			when cf.campaign_name_l like '%s_o_caetano%' then 'RMSP'
	 	    when cf.campaign_name_l like '%rio de janeiro%' then 'Rio de Janeiro'
	 	    when cf.campaign_name_l like '%niter_i%' then 'Rio de Janeiro'
	 	    when cf.campaign_name_l like '%campinas%' then 'Campinas'
	     	when cf.campaign_name_l like '%bh%' or cf.campaign_name_l like '%belo%h%' then 'Belo Horizonte'
	 	    when cf.campaign_name_l like '%minas_gerais%' then 'Belo Horizonte'
	     	when cf.campaign_name_l like '%goi_nia%' or cf.campaign_name_l like '%goi_s%' then 'Goiânia'
	     	when cf.campaign_name_l like '%bras_lia%' or cf.campaign_name_l like '%distrito_federal%' then 'Brasília'
	     	when cf.campaign_name_l like '%porto%alegre%' then 'Porto Alegre' 
	     	when cf.campaign_name_l like '%curitiba%' or cf.campaign_name_l like '%paran_%' then 'Curitiba'
	     	when cf.campaign_name_l like '%florian_polis%' or cf.campaign_name_l like '%santa_catarina%' then 'Florianópolis'
		end as city_campaign_mapping_rule,
		-- city via campaign_name name convention
		case when campaign_city in ('sp', 'jui', 'santo_andre', 'guarulhos', 'osasco', 'sao_caetano', 'sao_bernardo', 'barueri', 'rmsp') then 'RMSP'
			 when campaign_city = 'campinas' then 'Campinas'
			 when campaign_city in ('rj', 'niteroi', 'rio_de_janeiro', 'rio') then 'Rio de Janeiro'
			 when campaign_city in ('bh', 'belo_horizonte') then 'Belo Horizonte'
			 when campaign_city = 'goiania' then 'Goiânia'
			 when campaign_city in ('poa', 'porto_alegre') then 'Porto Alegre'
			 when campaign_city = 'curitiba' then 'Curitiba'
			 when campaign_city in ('fln', 'florianopolis') then 'Florianópolis'
			 when campaign_city in ('bsb', 'brasilia') then 'Brasília'
		end as campaign_city_matched,
		-- defining final city_group
	    coalesce(cost_city_group,city_campaign_mapping_rule, campaign_city_matched,'Not Mapped') as city_group_final,
	    tx.mkt_category,
	    tx.mkt_flow,
	    tx.mkt_completion,
	    tx.mkt_channel,
	    tx.mkt_medium,
	    tx.mkt_source,
	    tx.mkt_platform,
	    tx.fator_custo,
	    cf.utm_campaign,
		cf.utm_term,
		cf.utm_content,
		case when total_cost is null then
			case when tx.mkt_platform = 'Mobile' then mobile_cost
				 when tx.mkt_platform = 'Desktop' then desktop_cost
				 when tx.mkt_platform = 'Other' then other_cost
			end   
			else total_cost end
			* cast(coalesce(fator_custo, '0') as numeric(3,2))
			as cost,
		case when ((coalesce(cf.account_name_l,'') like '%supply%' or coalesce(cf.account_name_l,'') like '%display%')
					and coalesce(cf.account_name_l,'') != 'supply_affiliates')
					OR
					-- abbreviation rule
					(SPLIT_PART(cf.campaign_name, '.', 2) = 'S'
						or SPLIT_PART(cf.campaign_name, '.', 1) = '0'
						or SPLIT_PART(cf.campaign_name, '_', 1) = '0') then 'supply'
			when (coalesce(cf.account_name,'') not like '%supply%' 
		            and coalesce(cf.account_name, '') not like '%display%'
		            and coalesce(cf.account_name, '') != 'indica_ai')
		            OR
		         (SPLIT_PART(cf.campaign_name, '.', 2) = 'D'
		         or SPLIT_PART(cf.campaign_name, '.', 1) in ('1','2','3','4')
		         or SPLIT_PART(cf.campaign_name, '_', 1) in ('1','2','3','4')) then 'demand'
		   end as side
	from campaigns_full cf
		left join datalake_raw.mkt_cost_campaign_city as mccc
			on lower(mccc.campaign_name) = cf.campaign_name_l
		left join datalake_raw.taxonomy_mkt_cost as tx 
			on coalesce(cf.account_name, '') = coalesce(tx.account_name, '') 
				and cf.fact_cost = tx.fact_cost
				and cf.origin = tx.origin
)
select 
sk_date,
side as funnel_side,
account_name,
campaign_name,
city_group_final as city_group,
mkt_category,
mkt_flow,
mkt_completion,
mkt_channel,
mkt_medium,
mkt_source,
mkt_platform,
utm_campaign,
utm_term,
utm_content,
cost,
getdate() as ts_load
from demand_tax