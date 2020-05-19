select
    _id as id,
    nullif(userId, 'null') as id_user,
    status,
    extraInfo as extra_info,
    sentNotifications as sent_notifications,
    cast(regexp_extract(lastStatusChangedDate, '(\\d{{4}}-\\d{{2}}-\\d{{2}}\\w{{1}}\\d{{2}}:\\d{{2}}:\\d{{2}})', 1) as timestamp) as ts_last_status_changed,
    year,
    month,
    day
from datalake_jaiminho_raw.notificationentities
where year={year} and month={month} and day={day}