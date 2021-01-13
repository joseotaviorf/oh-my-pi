select
    code as id,
    name as campaign_name,
    description,
    detractors,
    passives,
    promoters,
    dispatches,
    answers,
    comments,
    main_channel,
    tags,
    questions,
    dispatch_limits,
    cast(create_time as timestamp) as ts_created
from
    datalake_tracksale_raw.campaign