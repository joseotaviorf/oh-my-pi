/*
Table with experiment names, dates and variants in usable manner to be used in other processes
*/

SELECT
    experiment_name,
    config.begin_date,
    config.end_date,
    regexp_replace(_variant_name, '"', '') AS variant_name,
    regexp_replace(variants[_variant_name], '"', '') as variant_standard_name
    FROM (
        SELECT
            *,
            explode(map_keys(str_to_map(regexp_replace(config.variants, '\\{{|\\}}', '' )))) AS _variant_name,
            str_to_map(regexp_replace(config.variants, '\\{{|\\}}', '' )) AS variants
        FROM
            datalake_search.experiment_config
        WHERE
            (DATE_SUB(DATE('{start_date}'), {days_past_30}) <= config.end_date OR config.end_date IS NULL)
            AND DATE('{end_date}') >= config.begin_date
    )
