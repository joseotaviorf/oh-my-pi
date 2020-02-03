alter table {db}.{table_name}
  add columns ({column_prefix}{column_formatted} {column_type} comment '{original_column}')
;