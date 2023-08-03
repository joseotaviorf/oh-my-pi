SELECT
    id,
    property_id AS id_property,
    owner_id AS id_owner,
    FROM_JSON(address,
        'city STRING,
        address STRING,
        zipCode STRING,
        complement STRING,
        addressNumber STRING,
        neighbourhood STRING,
        location STRUCT<lat STRING, lon STRING>'
    ) AS address,
    FROM_JSON(context_ownership,
        'SALE STRING,
        RENT STRING'
        ) AS context_ownership,
    FROM_JSON(context_property_status,
        'SALE STRING,
        RENT STRING'
        ) AS context_property_status,
    is_same_property_owner,
    similarity_score,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_property_dedup_raw.similar_property
QUALIFY
    ROW_NUMBER() OVER(PARTITION BY id ORDER BY dt DESC) = 1