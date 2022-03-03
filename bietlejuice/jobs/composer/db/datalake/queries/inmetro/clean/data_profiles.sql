select
    repo,
    case
        when repo = "wonka" then "feature_sets"
        when substr(database, -4) = "_raw" then "raw"
        when substr(database, -6) = "_clean" then "clean"
        when substr(database, 1, 10) = "dw_staging" then "dw_staging"
        else "enrich"
    end as layer,
    database,
    table,
    inmetro_info,
    year,
    month,
    day
from
    datalake_inmetro_raw.data_profiles
where
    year = {year}
    and month = {month}
    and day = {day}