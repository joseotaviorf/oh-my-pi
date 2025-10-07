SELECT
    NULLIF(Province, '') AS state,
    NULLIF(City, '') AS city,
    NULLIF(Zone, '') AS zone,
    NULLIF(SubZone, '') AS sub_zone,
    LOWER(
        REGEXP_REPLACE(
            TRANSLATE(
                Province,
                'áàãâäéèêëíìîïóòõôöúùûüçñÁÀÃÂÄÉÈÊËÍÌÎÏÓÒÕÔÖÚÙÛÜÇÑ',
                'aaaaaeeeeiiiiooooouuuucnAAAAAEEEEIIIIOOOOOUUUUCN'
            ),
        '[^a-zA-Z0-9 ]',
        ''
    )
  ) AS state_clean,
  LOWER(
        REGEXP_REPLACE(
            TRANSLATE(
                City,
                'áàãâäéèêëíìîïóòõôöúùûüçñÁÀÃÂÄÉÈÊËÍÌÎÏÓÒÕÔÖÚÙÛÜÇÑ',
                'aaaaaeeeeiiiiooooouuuucnAAAAAEEEEIIIIOOOOOUUUUCN'
            ),
        '[^a-zA-Z0-9 ]',
        ''
    )
  ) AS city_clean,
  LOWER(
        REGEXP_REPLACE(
            TRANSLATE(
                Zone,
                'áàãâäéèêëíìîïóòõôöúùûüçñÁÀÃÂÄÉÈÊËÍÌÎÏÓÒÕÔÖÚÙÛÜÇÑ',
                'aaaaaeeeeiiiiooooouuuucnAAAAAEEEEIIIIOOOOOUUUUCN'
            ),
        '[^a-zA-Z0-9 ]',
        ''
    )
  ) AS zone_clean,
 LOWER(
        REGEXP_REPLACE(
            TRANSLATE(
                SubZone,
                'áàãâäéèêëíìîïóòõôöúùûüçñÁÀÃÂÄÉÈÊËÍÌÎÏÓÒÕÔÖÚÙÛÜÇÑ',
                'aaaaaeeeeiiiiooooouuuucnAAAAAEEEEIIIIOOOOOUUUUCN'
            ),
        '[^a-zA-Z0-9 ]',
        ''
    )
  ) AS sub_zone_clean
FROM
    datalake_gsheets_raw.mexico_regions