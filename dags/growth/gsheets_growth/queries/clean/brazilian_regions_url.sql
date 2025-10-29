SELECT
    iw_region_url AS url_imovelweb_region,
    wi_region_url AS url_wimoveis_region,
    cm_region_url AS url_casamineira_region,
    state,
    city,
    neighborhood
FROM
    datalake_gsheets_raw.brazilian_regions_url