select
  phone,
  max(contacted) as contacted,
  max(if(contacted = 1, contact_time, null)) as contact_time
from
  (
    select
      telefoneAnunciante as phone,
      case
        when status {status_in} in ('{status_rule}') then 1
        when reason {reason_in} in ('{reason_rule}') then 1
        else 0
      end as contacted,
      atualizadoEm as contact_time
    from Lead
      where DATE_SUB(utc_timestamp(), INTERVAL {week_interval} WEEK) <= atualizadoEm
    union all
    select
      telefoneAnuncianteDois,
      case
        when status {status_in} in ('{status_rule}') then 1
        when reason {reason_in} in ('{reason_rule}') then 1
        else 0
      end as contacted,
      atualizadoEm as contact_time
    from Lead
      where DATE_SUB(utc_timestamp(), INTERVAL {week_interval} WEEK) <= atualizadoEm
    union all
    select
      telefoneAnuncianteTres,
      case
        when status {status_in} in ('{status_rule}') then 1
        when reason {reason_in} in ('{reason_rule}') then 1
        else 0
      end as contacted,
      atualizadoEm as contact_time
    from Lead
      where DATE_SUB(utc_timestamp(), INTERVAL {week_interval} WEEK) <= atualizadoEm
  ) contact
where phone is not null
  and phone <> ''
group by 1