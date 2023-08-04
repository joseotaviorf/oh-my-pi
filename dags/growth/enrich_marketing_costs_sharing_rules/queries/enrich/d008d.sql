SELECT /*+ RANGE_JOIN(adt, 300) */ DISTINCT
    adt.id_date,
    '{id_rule}' AS id_rule,
    rgn.city_group AS city_group,
    (DENSE_RANK() OVER(PARTITION BY adt.id_date, rgn.city_group ORDER BY hls.id_house_listing) +
     DENSE_RANK() OVER(PARTITION BY adt.id_date, rgn.city_group ORDER BY hls.id_house_listing DESC) - 1) /
     FLOAT(
        DENSE_RANK() OVER(PARTITION BY adt.id_date ORDER BY hls.id_house_listing) +
        DENSE_RANK() OVER(PARTITION BY adt.id_date ORDER BY hls.id_house_listing DESC) - 1
    ) AS share,
    'demand' AS funnel_side,
    CAST(NULL AS STRING) AS business_context
FROM
    datalake_quintoandar.aux_date AS adt
INNER JOIN
    datalake_ebdb_listing.house_listing_status AS hls
        ON adt.date BETWEEN DATE(hls.ts_status_started) AND DATE(COALESCE(hls.ts_status_ended, DATE_SUB(CURRENT_DATE(),2)))
        AND hls.status_history = 'PUBLISHED'
        AND hls.ts_status_started IS NOT NULL
INNER JOIN
    datalake_region.region AS rgn
        ON rgn.id = COALESCE(hls.id_region, -1)
        AND rgn.city_group IN (
            'Brasília',
            'Curitiba',
            'Florianópolis',
            'RMSP',
            'Rio de Janeiro'
        )