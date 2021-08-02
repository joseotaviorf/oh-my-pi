SELECT
    INT(NULLIF(id_insertion_order, '')) AS id_insertion_order,
    NULLIF(media, '') AS media,
    NULLIF(network, '') AS network,
    NULLIF(short_region_name, '') AS short_region_name,
    NULLIF(city_name, '') AS city_name,
    NULLIF(channel, '') AS channel,
    NULLIF(program, '') AS program,
    NULLIF(frequency, '') AS program_frequency,
    NULLIF(hour_started, '') AS program_hour_started,
    NULLIF(hour_ended, '') AS program_hour_ended,
    NULLIF(genre, '') AS program_genre,
    NULLIF(daypart, '') AS program_daypart,
    NULLIF(creative, '') AS creative_name,
    NULLIF(ad_description, '') AS ad_description,
    NULLIF(ad_type, '') AS ad_type,
    FLOAT(NULLIF(cost, '')) AS cost,
    FLOAT(NULLIF(grp, '')) AS grp,
    FLOAT(NULLIF(trp, '')) AS trp,
    DATE(NULLIF(dt_insertion_order, '')) AS dt_insertion_order,
    DATE(NULLIF(dt_started, '')) AS dt_started,
    DATE(NULLIF(dt_ended, '')) AS dt_ended
FROM
    datalake_gsheets_raw.media_plan