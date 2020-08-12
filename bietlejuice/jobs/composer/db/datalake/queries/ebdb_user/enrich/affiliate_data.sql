select
    ad.id,
    ad.id_indicated_by,
    ad.is_active,
    ad.origin,
    case when ad.affiliate_type = 'Doorman' and u.id_agent is not null then 'Doorman & Agent'
         when u.id_affiliates is not null then 'Agent'
         else ad.affiliate_type
    end as affiliate_type,
    ad.ts_operation_start,
    ad.ts_created,
    ad.ts_updated
from datalake_ebdb_clean.affiliate_data ad
left join datalake_ebdb_clean.user u
    on u.id_affiliates = ad.id
