select distinct
    id as sk_ad_group,
    id as id_ad_group,
    name as ad_group_name,
    current_timestamp as ts_load
from datalake_clean.marketing_twitter_ad_groups
-- filtering out accounts that have mixed taxonomy levels
where acc <> '18ce54ealak';