with cities_share_by_ol as (
    select distinct
        dd.sk_date,
        dr.city_group,
        (dense_rank() over (partition by dd.sk_date, dr.city_group order by fhs.sk_house_listing) +
            dense_rank() over (partition by dd.sk_date, dr.city_group order by fhs.sk_house_listing desc) - 1) /
        (dense_rank() over (partition by dd.sk_date order by fhs.sk_house_listing) +
            dense_rank() over (partition by dd.sk_date order by fhs.sk_house_listing desc) - 1)::float as share
    from dim_date dd
    join fact_house_listing_status fhs
        on dd.sk_date between fhs.sk_status_start_date and coalesce(nullif(fhs.sk_status_end_date, -1), to_char(current_date - 1, 'YYYYMMDD')::bigint)
        and fhs.status_history = 'publicado'
        and fhs.sk_status_start_date != -1
    join dim_region dr
        on dr.sk_region = fhs.sk_region
        and city_group is not null
    where dd.sk_date between 20180101 and cast(TO_CHAR(getdate() -1, 'YYYYMMDD') as integer)
),
manual_google_costs as (
    with t_prep as (
        select
          replace(replace(lower(f_remove_accentuation(account_name)), ' - ', '_'), ' ', '_') as prep_account_name,
          campaign_name,
          to_char(cast(g.date as date), 'yyyyMMdd')::integer as sk_date,
          cast(replace(desktop_cost, ',', '') as numeric(10,2)) as desktop_cost,
          cast(replace(mobile_cost, ',', '') as numeric(10,2)) as mobile_cost,
          cast(replace(tablet_cost, ',', '') as numeric(10,2)) as tablet_cost
        from datalake_raw.gsheets_marketing_manual_costs_google g
    )
    select
        case when prep_account_name = 'quintoandar_display_and_video' then 'quintoandar_dra'
			else prep_account_name end as account_name,
		*
	    from t_prep
),
google_consolidated_cost as (
    with t_google as (
        select
            fg.sk_date,
            coalesce(dgk.campaign_name, dga.campaign_name, dgc.campaign_name) as campaign_name,
            coalesce(dgk.account_name, dga.account_name, dgc.account_name) as account_name,
            dgk.keyword_name || '_' || lower(left(dgk.match_type, 1)) as utm_term,
            cast(dga.ad_id as varchar) as utm_content,
            fg.desktop_cost,
            fg.mobile_cost
        from marketing.fact_google_daily_cost_attributions fg
        left join marketing.dim_google_keyword dgk
            on dgk.sk_keyword = fg.sk_keyword
        left join marketing.dim_google_ad dga
            on dga.sk_ad = fg.sk_ad
        left join marketing.dim_google_campaign dgc
            on dgc.sk_campaign = fg.sk_campaign
        )
    select
		coalesce(m.sk_date, g.sk_date) as sk_date,
		case when m.sk_date is not null then m.campaign_name
		    else g.campaign_name end
		    as campaign_name,
		case when m.sk_date is not null then m.account_name
		    else g.account_name end
		    as account_name,
		case when m.sk_date is not null then m.campaign_name
		    else g.campaign_name end
		    as utm_campaign,
		case when m.sk_date is null then g.utm_term end
		    as utm_term,
		case when m.sk_date is null then g.utm_content end
		    as utm_content,
		case when m.sk_date is not null then m.desktop_cost
		    else g.desktop_cost end
		    as desktop_cost,
		case when m.sk_date is not null then m.mobile_cost
		    else g.mobile_cost end
		    as mobile_cost
	from t_google g
	full outer join manual_google_costs m
	    on m.sk_date = g.sk_date
	    and m.account_name = g.account_name
	    and m.campaign_name = g.campaign_name
	where coalesce(m.sk_date, g.sk_date) >= 20180101
),
campaigns_full as (
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
		sk_date,
		'google' as origin,
		'fact_google_daily_cost_attributions' as fact_cost,
		campaign_name,
		lower(case when SPLIT_PART(campaign_name, '.', 2) ~ '^[0-9]+$' then
		    SPLIT_PART(campaign_name, '.', 3)
		    else
		    SPLIT_PART(campaign_name, '.', 2)
		    end) as campaign_city,
		account_name,
		lower(campaign_name) as campaign_name_l,
		lower(account_name) as account_name_l,
		cast(utm_campaign as varchar) as utm_campaign,
		cast(utm_term as varchar) as utm_term,
		cast(utm_content as varchar) as utm_content,
		desktop_cost,
		mobile_cost,
		null as other_cost,
		null as total_cost
	from google_consolidated_cost
UNION (
    -- selects costs from each cities, mapping campaigns to use OL share
    with trovit_city_costs as (
        select
            ftc.sk_date,
            dtc.campaign_name,
            case
                when lower(dtc.campaign_name) like '%campinas%' then 'Campinas'
                when lower(dtc.campaign_name) like '%s_o_paulo%' or lower(dtc.campaign_name) like '%sp detailed%' then 'RMSP'
                when lower(dtc.campaign_name) like 'sp %' then 'RMSP'
                when lower(dtc.campaign_name) like '%all cities%' then 'RMSP'
                when lower(dtc.campaign_name) like '%rmsp%' then 'RMSP'
                when lower(dtc.campaign_name) like '%guarulhos%' then 'RMSP'
                when lower(dtc.campaign_name) like '%abc%' then 'RMSP'
                when lower(dtc.campaign_name) like '%barueri%' then 'RMSP'
                when lower(dtc.campaign_name) like '%osasco%' then 'RMSP'
                when lower(dtc.campaign_name) like '%jundia%' then 'RMSP'
                when lower(dtc.campaign_name) like '%santo_andr%' then 'RMSP'
                when lower(dtc.campaign_name) like '%s_o_bernardo%' then 'RMSP'
                when lower(dtc.campaign_name) like '%s_o_caetano%' then 'RMSP'
                when lower(dtc.campaign_name) like '%rio_de_janeiro%' then 'Rio de Janeiro'
                when lower(dtc.campaign_name) like '%niter_i%' then 'Rio de Janeiro'
                when lower(dtc.campaign_name) like '%bh%' or lower(dtc.campaign_name) like '%belo%h%' then 'Belo Horizonte'
                when lower(dtc.campaign_name) like '%minas_gerais%' then 'Belo Horizonte'
                when lower(dtc.campaign_name) like '%goi_nia%' or lower(dtc.campaign_name) like '%goi_s%' then 'Goiânia'
                when lower(dtc.campaign_name) like '%bras_lia%' or lower(dtc.campaign_name) like '%distrito_federal%' then 'Brasília'
                when lower(dtc.campaign_name) like '%porto%alegre%' then 'Porto Alegre'
                when lower(dtc.campaign_name) like '%curitiba%' or lower(dtc.campaign_name) like '%paran_%' then 'Curitiba'
                when lower(dtc.campaign_name) like '%florian_polis%' or lower(dtc.campaign_name) like '%santa_catarina%' then 'Florianópolis'
                else 'SHARE_BY_OL_CITIES'
            end as city_group,
            ftc.desktop_cost as desktop_cost,
            ftc.mobile_cost as mobile_cost
        from marketing.fact_trovit_daily_cost_attributions ftc
        left join marketing.dim_trovit_campaign dtc
            on ftc.sk_trovit_campaign = dtc.sk_trovit_campaign
        where ftc.sk_date >= 20180101
    ),
    -- adds OL share to the campaigns not mapped from campaign name
    trovit_share_by_ol_cities as (
        select
            tcc.sk_date,
            tcc.campaign_name,
            csol.city_group as city_group,
            tcc.desktop_cost * csol.share  as desktop_cost,
            tcc.mobile_cost * csol.share as mobile_cost
        from trovit_city_costs as tcc
        join cities_share_by_ol csol
            on tcc.sk_date = csol.sk_date
        where tcc.city_group = 'SHARE_BY_OL_CITIES'
    )
    -- merges campaigns with city mapped and from OL (not mapped)
    select
        sk_date,
        'trovit' as origin,
        'fact_trovit_daily_cost_attributions' as fact_cost,
        campaign_name,
        null as campaign_city,
        null as account_name,
        city_group as campaign_name_l,
        null as account_name_l,
        null as utm_campaign,
        null as utm_term,
        null as utm_content,
        desktop_cost,
        mobile_cost,
        null as other_cost,
        null as total_cost
    from (
        select * from trovit_city_costs where city_group != 'SHARE_BY_OL_CITIES'
        union all
        select * from trovit_share_by_ol_cities
    )
)
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
        null as campaign_city,
        drt.account_name as account_name,
        lower(drt.campaign_name) as campaign_name_l,
        lower(drt.account_name) as account_name_l,
        null as utm_campaign,
        null as utm_term,
        null as utm_content,
        sum(coalesce(case when device = 'Desktop' then cost end, 0)) as desktop_cost,
        sum(coalesce(case when device = 'Mobile' then cost end, 0)) as mobile_cost,
        sum(coalesce(case when device = 'Other' then cost end, 0)) as other_cost,
        null as total_cost
      from marketing.fact_rtb_daily_cost_attributions frt
      left join marketing.dim_rtb_sub_campaign drt
      	on frt.sk_sub_campaign = drt.sk_sub_campaign
      where frt.sk_date >= 20180101
      group by 1,2,3,4,5,6,7,8,9,10,11
UNION
    select
        fcl.sk_date,
        dcl.name as origin,
        'fact_classified_daily_cost_attributions' as fact_cost,
        null as campaign_name,
        csol.city_group as campaign_city,
        null as account_name,
        null as campaign_name_l,
        null as account_name_l,
        null as utm_campaign,
        null as utm_term,
        null as utm_content,
        null as desktop_cost,
        null as mobile_cost,
        null as other_cost,
        fcl.cost * csol.share as total_cost
      from marketing.fact_classified_daily_cost_attributions fcl
      left join marketing.dim_classified dcl on fcl.sk_classified = dcl.sk_classified
      left join cities_share_by_ol csol on csol.sk_date = fcl.sk_date
      -- filter with 'between' because there is future cost
      where fcl.sk_date between 20180101 and cast(TO_CHAR(getdate() -1, 'YYYYMMDD') as integer)
UNION
    select
        ftw.sk_date,
        'twitter' as origin,
        'fact_twitter_daily_cost_attributions' as fact_cost,
        dtwc.campaign_name,
        null as campaign_city,
        dtwc.account_name as account_name,
        lower(dtwc.campaign_name) as campaign_name_l,
        lower(dtwc.account_name) as account_name_l,
        replace(dtwc.campaign_name, ' ', '_') as utm_campaign,
        upper(dtag.ad_group_name) as utm_term,
        null as utm_content,
        sum(desktop_cost) as desktop_cost,
        sum(mobile_cost) as mobile_cost,
        sum(other_cost) as other_cost,
        null as total_cost
    from marketing.fact_twitter_daily_cost_attributions ftw
    join marketing.dim_twitter_campaign dtwc
        on ftw.sk_campaign = dtwc.sk_campaign
    join marketing.dim_twitter_ad_group dtag
        on ftw.sk_ad_group = dtag.sk_ad_group
    where ftw.sk_date >= 20180101
    group by 1,2,3,4,5,6,7,8,9,10,11
UNION
    select
        fli.sk_date,
        'linkedin' as origin,
        'fact_linkedin_daily_cost_attributions' as fact_cost,
        dlc.campaign_name,
        null as campaign_city,
        dlc.account_name as account_name,
        lower(dlc.campaign_name) as campaign_name_l,
        lower(dlc.account_name) as account_name_l,
        dlc.campaign_name as utm_campaign,
        null as utm_term,
        null as utm_content,
        null as desktop_cost,
        null as mobile_cost,
        null as other_cost,
        sum(total_spent) as total_cost
    from marketing.fact_linkedin_daily_cost_attributions fli
    join marketing.dim_linkedin_campaign dlc
        on dlc.sk_campaign = fli.sk_campaign
    group by 1,2,3,4,5,6,7,8,9,10,11
)
,cost_taxonomy as (
	select
		cf.origin,
		cf.sk_date,
		cf.account_name,
		cf.campaign_name,
		-- city via manual mapping
		mccc.city_group as cost_city_group,
		-- city via campaign_name full name written
		case
		    when campaign_name_l in ('Florianópolis', 'Curitiba', 'Goiânia', 'Rio de Janeiro', 'RMSP', 'Belo Horizonte', 'Brasília', 'Campinas', 'Porto Alegre')
		        then campaign_name_l
	 	    when cf.campaign_name_l like '%campinas%' then 'Campinas'
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
	 	    when cf.campaign_name_l like '%rio%de%janeiro%' then 'Rio de Janeiro'
	 	    when cf.campaign_name_l like '%niter_i%' then 'Rio de Janeiro'
	     	when cf.campaign_name_l like '%bh%' or cf.campaign_name_l like '%belo%h%' then 'Belo Horizonte'
	 	    when cf.campaign_name_l like '%minas_gerais%' then 'Belo Horizonte'
	     	when cf.campaign_name_l like '%goi_nia%' or cf.campaign_name_l like '%goi_s%' then 'Goiânia'
	     	when cf.campaign_name_l like '%bras_lia%' or cf.campaign_name_l like '%distrito_federal%' then 'Brasília'
	     	when cf.campaign_name_l like '%porto%alegre%' then 'Porto Alegre' 
	     	when cf.campaign_name_l like '%curitiba%' or cf.campaign_name_l like '%paran_%' then 'Curitiba'
	     	when cf.campaign_name_l like '%florian_polis%' or cf.campaign_name_l like '%santa_catarina%' then 'Florianópolis'
	     	when cf.campaign_name_l like '%poa%' then 'Porto Alegre'
	     	when cf.campaign_name_l like '%ctba%' then 'Curitiba'
	     	when cf.campaign_name_l like '%fln%' then 'Florianópolis'
	     	when cf.campaign_name_l like '%cps%' then 'Campinas'
	     	when cf.campaign_name_l like '%bsb%' then 'Brasília'
	     	when cf.campaign_name_l like '%rj%' then 'Rio de Janeiro'
		end as city_campaign_mapping_rule,
		-- city via campaign_name name convention
		case
             when campaign_city in ('Florianópolis', 'Curitiba', 'Goiânia', 'Rio de Janeiro', 'RMSP', 'Belo Horizonte', 'Brasília', 'Campinas', 'Porto Alegre')
		        then campaign_city
		     when campaign_city = 'campinas' then 'Campinas'
		     when campaign_city in ('sp', 'jui', 'santo_andre', 'guarulhos', 'osasco', 'sao_caetano', 'sao_bernardo', 'barueri', 'rmsp') then 'RMSP'
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
	    -- due to higher granularity it was not possible to add this column in taxonomy table
	    case when tx.side = 'supply' and cf.campaign_name_l like '%calculadora%' then 'PriceSuggestion'
	         when tx.side = 'supply' then 'OwnerPWA'
	    end as mkt_origin,
	    tx.mkt_channel,
	    tx.mkt_medium,
	    tx.mkt_source,
	    tx.mkt_platform,
	    tx.fator_custo,
	    cf.utm_campaign,
		cf.utm_term,
		cf.utm_content,
		case
		    when total_cost is null then
                case when tx.mkt_platform = 'Mobile' then mobile_cost
                     when tx.mkt_platform = 'Desktop' then desktop_cost
                     when tx.mkt_platform = 'Other' then other_cost
                end
            else total_cost
        end * cast(coalesce(fator_custo, '0') as numeric(3,2)) as cost,
        case
            -- cases with supply and demand costs in the same account
            when cf.origin in ('google', 'facebook', 'trovit') then
                    case
                        when ((coalesce(cf.account_name_l,'') like '%supply%' or coalesce(cf.account_name_l,'') like '%display%')
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
                        else tx.side
                    end
            else tx.side
            end as side
	from campaigns_full cf
		left join datalake_raw.gsheets_marketing_cost_campaign_city as mccc
			on lower(mccc.campaign_name) = cf.campaign_name_l
		left join datalake_raw.gsheets_taxonomy_mkt_cost as tx
			on coalesce(cf.account_name, '') = coalesce(tx.account_name, '') 
				and cf.fact_cost = tx.fact_cost
				and cf.origin = tx.origin
), kenshoo as (
	select
		ct.sk_date,
		ct.side as funnel_side,
		tx.account_name as account_name,
		ct.city_group_final as city_group,
		tx.mkt_category,
		tx.mkt_flow,
		tx.mkt_completion,
		tx.mkt_channel,
		tx.mkt_medium,
		tx.mkt_source,
		tx.mkt_platform,
		ct.cost * cast(k.rate as float) as cost
	from cost_taxonomy ct
    join datalake_raw.gsheets_marketing_kenshoo_configuration k
		on	ct.mkt_source = k.mkt_source
		and ct.mkt_medium = k.mkt_medium
		and ct.sk_date between
			cast(to_char(to_date(k.date_from, 'MM/DD/YYYY'), 'YYYYMMDD') as integer)
			and
			cast(to_char(to_date(k.date_until, 'MM/DD/YYYY'), 'YYYYMMDD') as integer)
	left join datalake_raw.gsheets_taxonomy_mkt_cost as tx
			on tx.origin = 'kenshoo'
			and tx.side = ct.side
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
    mkt_origin,
    mkt_channel,
    mkt_medium,
    mkt_source,
    mkt_platform,
    utm_campaign,
    utm_term,
    utm_content,
    cost,
    getdate() as ts_load
from cost_taxonomy
union all
select
    sk_date,
    funnel_side,
    account_name,
    null as campaign_name,
	city_group,
    mkt_category,
    mkt_flow,
    mkt_completion,
    null as mkt_origin,
    mkt_channel,
    mkt_medium,
    mkt_source,
    mkt_platform,
    null as utm_campaign,
    null as utm_term,
    null as utm_content,
    sum(cost) as cost,
    getdate() as ts_load
from kenshoo
group by 1,2,3,5,6,7,8,10,11,12,13