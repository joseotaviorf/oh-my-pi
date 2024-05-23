SELECT 
    id,
    house_id AS id_house,
    rev,
    revtype AS rev_type,
    priceTrend AS price_trend,
    priceTrend_MOD AS mod_price_trend,
    criadoEm AS ts_created,
    lastPriceUpdate AS ts_last_price_updated,
    atualizadoEm AS ts_updated
FROM
    datalake_ebdb_raw.houserentcosts_aud