select distinct
    id as sk_ad,
    id as id_ad,
    tweet_id,
    current_timestamp as ts_load
from datalake_clean.marketing_twitter_ads;