select
    id,
    externaldomain AS external_domain,
    externaldomainid AS id_external_domain,
    metadata,
    sourceid AS id_source,
    videosource AS video_source
from datalake_kodak_raw.video
