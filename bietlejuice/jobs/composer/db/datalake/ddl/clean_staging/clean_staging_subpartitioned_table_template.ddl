CREATE TABLE IF NOT EXISTS
    `{clean_staging_db}`.`{subpartitioned_table_name}`
LIKE
    `{clean_db}`.`{source_table_name}`
LOCATION
    '{clean_staging_source_path}{target_table_name}/{partition_values_path}'
