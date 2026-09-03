SELECT
    idaviso AS id_listing,
    idpais AS id_country,
    idplandepublicacion AS id_publication_plan,
    idareadepublicacion AS id_publication_area,
    tipo AS ranking_type,
    impresiones AS impression_count,
    impresionestotales AS total_impression_count,
    leads AS lead_count,
    leadstotales AS total_lead_count,
    ctdadregistros AS record_count,
    ctdadregistrostotales AS total_record_count,
    peso AS ranking_weight,
    scoreleads AS lead_score,
    score AS ranking_score,
    convertionrate AS conversion_rate,
    ranking AS ranking_position,
    rankingnew AS new_ranking_position,
    fechacreacion AS ts_created,
    fechapublicacion AS ts_published,
    fechamodificado AS ts_updated
FROM
    datalake_realestate_raw.avisosrealestateranking
