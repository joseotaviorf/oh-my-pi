SELECT
    id AS id_qa_listing_client,
    fkempresa AS id_company,
    fkimovel AS id_house,
    houseId AS id_house_api,
    detailViewUrl AS detail_view_url,
    activeDb AS is_active_db,
    updateDate AS dt_updated,
    createDateDb AS ts_created_db,
    updateDateDb AS ts_updated_db
FROM
    datalake_union_cdc_raw.qa_listing_client
