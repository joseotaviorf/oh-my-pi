WITH
  remove_ebdb_replica AS (
    SELECT
      datasource,
      table_full_qualified_name,
      column_name,
      data_type,
      classifications
    FROM 
      datalake_bigid_clean.data_catalog_entities
    WHERE
      datasource != "EBDB_REPLICA"
  ),
  exploded_classifications AS
  (
    SELECT
      LOWER(datasource) AS datasource,
      LOWER(table_full_qualified_name) AS table_full_qualified_name,
      LOWER(column_name) AS column_name,
      data_type,
      explode_outer(from_json(classifications, "ARRAY<STRING>")) AS classification
    FROM 
      remove_ebdb_replica
  ),
  split_names AS
  (
    SELECT
--    These coalesces are used to split database type and database name. Ex: MONGO_CYCLOPS_PROD, RDS_FASTFORWARD.
--    Some DBs don't end with _PROD, so we need to use two different regexes to match them.
      COALESCE(NULLIF(regexp_extract(datasource, '(.*)[_-](.*)[_-](.*)' , 1), ''), NULLIF(regexp_extract(datasource, '(.*)[_-](.*)' , 1), '') ) AS database_type,
      COALESCE(NULLIF(regexp_extract(datasource, '(.*)[_-](.*)[_-](.*)' , 2), ''), NULLIF(regexp_extract(datasource, '(.*)[_-](.*)' , 2), '') ) AS database_name,
--    Table name is the last name in table_full_qualified_name, e.g. the table usuario from EBDB would have table_full_qualified_name = "RDS_EBDB_PROD.default.usuario".
      LOWER(split(table_full_qualified_name, "\\.")[2]) AS table_name,
--    Some columns are expanded to one extra depth level using a dot, e.g. a JSON column named metadata with a field "email" would be expanded to "metadata.email".
--    This regex extracts the first name only.
      regexp_extract(column_name, '(\\w+)?\.?(.*)?' , 1) AS column_name,
      LOWER(data_type) AS data_type,
--    Some classifications start with 'classifier.', e.g. "classifier.email", so we take the last name
      LOWER(reverse(split(classification, '\\.'))[0]) AS classification
    FROM
      exploded_classifications ec
  ),
  access_level_values AS
  (
    SELECT
      database_type,
      database_name,
      table_name,
      column_name,
      data_type,
      classification,
      CASE
        WHEN classification IN
        (
        'age',
        'brazilian driver\'s license number',
        'brazilian identity card number (minas gerais)',
        'brazilian identity card number (sao paulo)',
        'brazilian national health card number',
        'brazilian social identification number',
        'brazilian voter id number',
        'cpf',
        'name',
        'nome'
        ) THEN True
        ELSE Null
      END AS is_pii,
      CASE
        WHEN classification IN
        (
          'brazilian orientação sexual',
          'brazilian politica',
          'brazilian racial',
          'brazilian religião',
          'brazilian saúde',
          'brazilian sexual',
          'brazilian identidade de gênero'
        ) THEN True
        ELSE Null
      END AS is_sensitive,
      CASE
        WHEN classification IN
        (
          'brazilian driver\'s license number',
          'brazilian identidade de gênero' ,
          'brazilian identity card number (minas gerais)',
          'brazilian identity card number (sao paulo)',
          'brazilian idoso',
          'brazilian national health card number',
          'brazilian orientação sexual' ,
          'brazilian politica' ,
          'brazilian racial' ,
          'brazilian religião' ,
          'brazilian saúde' ,
          'brazilian sexual' ,
          'brazilian social identification number',
          'brazilian voter id number',
          'cpf',
          'email',
          'geographicdata',
          'ipv4',
          'ipv6',
          'mac address',
          'name',
          'nome',
          'public ipv4 address',
          'telefoneprincipal',
          'user_email'
        ) THEN 3
        WHEN classification IN
        ('age', 'brazilian menor 18 anos') THEN 2
--        currently there's no access level 1 tags in BigID
        ELSE 0
      END as access_level
    FROM
      split_names sn
  ),
  grouped_columns AS
  (
    SELECT
      database_type,
      database_name,
      table_name,
      column_name,
      data_type,
      COALESCE(FIRST(is_pii, True), False) AS is_pii,
      COALESCE(FIRST(is_sensitive, True), False) AS is_sensitive,
      CASE
        WHEN MAX(access_level) == 3 THEN 'Confidential'
        WHEN MAX(access_level) == 2 THEN 'Restricted'
        WHEN MAX(access_level) == 1 THEN 'Public'
        ELSE null
      END AS access_level,
      collect_set(classification) AS classifications
      FROM access_level_values alv
      GROUP BY
        database_type,
        database_name,
        table_name,
        column_name,
        data_type
  )
SELECT
  database_name,
  table_name,
  column_name,
  database_type,
  classifications,
  data_type,
  access_level,
  is_pii,
  is_sensitive
FROM
  grouped_columns
