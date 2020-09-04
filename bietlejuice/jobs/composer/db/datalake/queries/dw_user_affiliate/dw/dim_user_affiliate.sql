with affiliates_full as (
    select
        ad.id as sk_user_affiliate,
        ad.id as id_user_affiliate,
        ad.id_indicated_by as sk_user_indicated_by,
        u.id as id_user,
        ad.is_active,
        ad.origin,
        ad.affiliate_type,
        coalesce(agent_data.is_realstate_agent, false) as is_realstate_agent,
        coalesce(agent_data.is_photographer, false) as is_photographer,
        u.main_phone_ddd as main_phone_ddd,
        uao.utm_source as tracking_source,
        uao.utm_medium as tracking_medium,
        uao.utm_campaign as tracking_campaign,
        uao.utm_content as tracking_content,
        uao.utm_term as tracking_term,
        uao.city_campaign,
        uao.platform as tracking_platform,
        uao.device_type as tracking_device_type,
        uao.country as tracking_country,
        uao.region as tracking_state,
        uao.city as tracking_city,
        ad.ts_operation_start,
        ad.ts_created,
        ad.ts_updated
    from
        datalake_ebdb_user.affiliate_data ad
        join datalake_ebdb_user.user u
            on u.id_affiliates = ad.id
        left join datalake_amplitude_user.user_affiliate_origin uao
            on u.id = uao.id_user
        left join datalake_ebdb_user.agent_data
            on agent_data.id = u.id_agent
),
region_ddd as (
	select
	    distinct city_group,
		city_ddd as ddd,
		regional
	from
		datalake_region.region
	where is_city
),
region_city as (
	select
	    distinct city_name,
		city_group,
		regional
	from
		datalake_region.region
	where is_city
),
affiliate_mkt_city_group as (
	select
		af_full.*,
		coalesce(af_full.city_campaign, region_city.city_group, region_ddd.city_group) as marketing_city_group,
		coalesce(region_city.regional, region_ddd.regional) as regional_ddd_city
	from
		affiliates_full af_full
	left join region_city
		on af_full.tracking_city = region_city.city_name
	left join region_ddd
		on af_full.main_phone_ddd = region_ddd.ddd
),
aff_city_group_with_region as (
	select
		aff_city_region.sk_user_affiliate,
		aff_city_region.id_user_affiliate,
		aff_city_region.sk_user_indicated_by,
		aff_city_region.id_user,
		aff_city_region.origin,
		aff_city_region.affiliate_type,
		aff_city_region.marketing_city_group,
		coalesce(region_city_group.regional, aff_city_region.regional_ddd_city) as regional,
		nullif(aff_city_region.tracking_source, '') as tracking_source,
		nullif(aff_city_region.tracking_medium, '') as tracking_medium,
		nullif(aff_city_region.tracking_campaign, '') as tracking_campaign,
		nullif(aff_city_region.tracking_content, '') as tracking_content,
		nullif(aff_city_region.tracking_term, '') as tracking_term,
		aff_city_region.tracking_platform,
		aff_city_region.tracking_device_type,
		aff_city_region.tracking_country,
		aff_city_region.tracking_state,
		aff_city_region.tracking_city,
		aff_city_region.is_realstate_agent,
		aff_city_region.is_active,
		aff_city_region.is_photographer,
		aff_city_region.ts_operation_start,
		aff_city_region.ts_created,
		aff_city_region.ts_updated
	from
        affiliate_mkt_city_group aff_city_region
	left join region_ddd as region_city_group
        on aff_city_region.marketing_city_group = region_city_group.city_group
),
taxonomy as (
	select
		affiliate_type,
		tracking_medium,
		tracking_source,
		tracking_campaign,
		nullif(mkt_origin, '') as mkt_origin,
		nullif(mkt_channel, '') as mkt_channel,
		nullif(mkt_medium, '') as mkt_medium,
		nullif(mkt_source, '') as mkt_source
	from
		datalake_raw.gsheets_taxonomy_affiliates
),
applied_taxonomy as (
	select
		acg.*,
		coalesce(tax.mkt_origin, 'Other') as mkt_origin,
		coalesce(tax.mkt_channel, 'Not Mapped') as mkt_channel,
		coalesce(tax.mkt_medium, 'Not Mapped') as mkt_medium,
		coalesce(tax.mkt_source, 'Not Mapped') as mkt_source
	from
		aff_city_group_with_region acg
		left join taxonomy tax
			on coalesce(tax.affiliate_type, '') = coalesce(acg.affiliate_type, '')
			and coalesce(tax.tracking_medium, '') = coalesce(acg.tracking_medium, '')
			and coalesce(tax.tracking_source, '') = coalesce(acg.tracking_source, '')
			and coalesce(tax.tracking_campaign, '') = coalesce(acg.tracking_campaign, '')
)
select
	atax.sk_user_affiliate,
	atax.id_user as sk_user,
	atax.id_user_affiliate,
	atax.sk_user_indicated_by,
	atax.origin,
	atax.affiliate_type,
	atax.marketing_city_group,
	atax.regional,
	atax.tracking_source,
	atax.tracking_medium,
	atax.tracking_campaign,
	atax.tracking_content,
	atax.tracking_term,
	atax.tracking_platform,
	atax.tracking_device_type,
	atax.tracking_country,
	atax.tracking_state,
	atax.tracking_city,
	atax.mkt_origin,
	atax.mkt_channel,
	atax.mkt_medium,
	atax.mkt_source,
	atax.is_realstate_agent,
	atax.is_photographer,
	atax.is_active,
	atax.ts_operation_start,
	atax.ts_created,
	atax.ts_updated,
	now() as ts_load
from
	applied_taxonomy atax