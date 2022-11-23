select 
    domain,
    metabase_collection as dashboard_folder
from
    datalake_gsheets_raw.metabase_collections_domains
