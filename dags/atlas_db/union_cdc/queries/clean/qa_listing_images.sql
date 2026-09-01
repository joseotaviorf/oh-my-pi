SELECT
    id AS id_qa_listing_image,
    houseId AS id_house_api,
    description,
    url,
    urlThumb AS url_thumb,
    `order` AS display_order,
    main AS is_main,
    createDateDb AS ts_created_db,
    updateDateDb AS ts_updated_db
FROM
    datalake_union_cdc_raw.qa_listing_images
