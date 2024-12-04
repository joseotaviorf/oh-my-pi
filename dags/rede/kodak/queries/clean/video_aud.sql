SELECT
   id,
   rev,
   revtype AS rev_type,
   revend AS rev_end,
   externaldomain AS external_domain,
   externaldomainid AS id_external_domain,
   metadata,
   metadata_mod AS mod_metadata,
   sourceid AS id_source,
   sourceid_mod AS mod_id_source,
   videosource AS video_source,
   videosource_mod AS mod_video_source
 FROM
   datalake_kodak_raw.video_aud