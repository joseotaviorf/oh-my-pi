SELECT
    sk_criteo_campaign,
    id_campaign,
    advertiser_name,
    campaign_name,
    getdate() as ts_load
from staging.dim_criteo_campaign