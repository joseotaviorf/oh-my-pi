with first_operation_start (
    with min_operation_start_rev (
        select
            id_affiliate_data,
            min(REV) as REV
        from datalake_ebdb_clean.affiliate_data_aud
        where ts_operation_start is not null
        group by 1
	)
	select
	    ada.id_affiliate_data,
	    ada.ts_operation_start
	from min_operation_start_rev mosr
    left join datalake_ebdb_clean.affiliate_data_aud ada
        on mosr.id_affiliate_data = ada.id_affiliate_data
        and mosr.REV = ada.REV
)
select
    ad.id,
    ad.id_indicated_by,
    ad.is_active,
    (ad.id_doorman_affiliate_data is not null) as is_doorman_affiliate,
    ad.origin,
    case when ad.affiliate_type = 'Doorman' and u.id_agent is not null then 'Doorman & Agent'
         when u.id_affiliates is not null then 'Agent'
         else ad.affiliate_type
    end as affiliate_type,
    ad.payment_preference,
    ad.creci_number,
    coalesce(ad.operation_city, dad.work_city) as work_city,
    ad.last_week_balance_communication,
    coalesce(fos.ts_operation_start, ad.ts_operation_start) as ts_first_operation_start,
    ad.ts_operation_start,
    ad.ts_created,
    ad.ts_updated
from datalake_ebdb_clean.affiliate_data ad
left join datalake_ebdb_clean.user u
    on u.id_affiliates = ad.id
left join datalake_ebdb_clean.doorman_affiliate_data dad
    on dad.id = ad.id_doorman_affiliate_data
left join first_operation_start fos
    on fos.id_affiliate_data = ad.id