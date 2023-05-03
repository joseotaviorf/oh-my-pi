SELECT
    NULLIF(STRING(date),'')||' '||NULLIF(STRING(time),'') AS datetime_ad,
    NULLIF(STRING(broadcaster),'') AS broadcaster,
    NULLIF(STRING(city_group),'') AS city_group,
    NULLIF(STRING(tv_show),'') AS tv_show,
    NULLIF(STRING(creative),'') AS creative,
    NULLIF(FLOAT(size),'') AS size,
    NULLIF(FLOAT(cost),'') AS cost,
    NULLIF(FLOAT(grp),'') AS grp
FROM
    datalake_gsheets_raw.tv_ads