alter table datalake_clean.amplitude_events
  add columns ({column_prefix}{column_formatted} {column_type} comment '{original_column}')
;