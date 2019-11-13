select distinct
    id as sk_creative,
    id as id_creative,
    current_timestamp as ts_load
from datalake_clean.marketing_linkedin_creatives;