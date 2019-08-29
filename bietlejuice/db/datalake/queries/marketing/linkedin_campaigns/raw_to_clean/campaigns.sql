select distinct
    account_id as id_account,
    campaign_id as id_campaign,
    campaign_name,
    nullif(nullif(nullif(impressions, 'NA'), ''), 'null') as impressions,
    nullif(nullif(nullif(clicks, 'NA'), ''), 'null') as clicks,
    nullif(nullif(nullif(ctr, 'NA'), ''), 'null') as ctr,
    nullif(nullif(nullif(cpc, 'NA'), ''), 'null') as cpc
from datalake_raw.marketing_linkedin_campaigns
WHERE account_id='{account}'
    and dt='{date}'
    and cast(dt as date) = cast(try(date_parse(date_sk, '%m/%d/%Y')) as date)