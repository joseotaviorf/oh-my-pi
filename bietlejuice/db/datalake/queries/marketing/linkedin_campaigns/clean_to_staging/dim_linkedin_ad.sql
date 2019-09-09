select distinct
    id_ad as sk_ad,
    id_ad as id_ad,
    ad_name,
    current_timestamp as ts_load
from datalake_clean.marketing_linkedin_campaigns;