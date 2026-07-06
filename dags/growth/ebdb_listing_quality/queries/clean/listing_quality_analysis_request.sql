SELECT id,
       house_id AS id_house,
       analysis_requested,
       listing_quality_id AS id_listing_quality,
       criadoem AS ts_created,
       atualizadoem AS ts_updated,
       uploaded_by
FROM datalake_ebdb_raw.listingqualityanalysisrequest
