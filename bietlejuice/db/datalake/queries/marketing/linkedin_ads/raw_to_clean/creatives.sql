select
	id,
    split_part(campaign, ':', 4) as id_campaign,
    status,
    type
from datalake_raw.marketing_linkedin_creatives
WHERE dt='{date}' and acc='{account}'