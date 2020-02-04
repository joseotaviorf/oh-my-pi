alter table datalake_amplitude_clean_prod.events
  add columns ({column_prefix}{column_formatted} {column_type} comment '{original_column}')
;