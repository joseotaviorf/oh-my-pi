SELECT
    id_post_wordpress,
    id_author,
    'meulugar_data' AS table_source,
    author_meta:display_name AS author_name,
    CASE
        WHEN author_meta:display_name IN (
            'Raphael','Carlos','João Gabriel','Lua Amaro','Lorenah Spata','Welton Azevedo','Carlos Padrão','Camila Claro','Raphael Crespo','Yago Barbosa'
            )
            THEN 'BAROES'
        WHEN author_meta:display_name IN (
            'Adonai Marcondes','Laura Bernardes','Charles'
            )
            THEN 'HDD'
        ELSE author_meta:display_name
    END AS author_group,
    REGEXP_EXTRACT_ALL(tax_additional:tags:linked, '(?<=>)[^<]+(?=<\\/a>)',0) AS tags,
    REGEXP_EXTRACT_ALL(tax_additional:categories:linked, '(?<=>)[^<]+(?=<\\/a>)',0) AS categories,
    slug,
    title,
    acf_funnel,
    acf_user_type,
    DATEDIFF(dt_post_modified,dt_post_created) AS day_diff_create_modified,
    DATEDIFF(dt_post_modified,dt_post_created) > 90 AS has_changes_after_90_days,
    dt_post_created,
    dt_post_modified
FROM
    datalake_wordpress_baroes_clean.meulugar_data
QUALIFY 
    ROW_NUMBER() OVER(PARTITION BY id_post_wordpress ORDER BY dt_post_modified DESC) = 1
UNION ALL
SELECT
    id_post_wordpress,
    id_author,
    'conteudos_data' AS table_source,
    author_meta:display_name AS author_name,
    CASE
        WHEN author_meta:display_name IN (
            'Raphael','Carlos','João Gabriel','Lua Amaro','Lorenah Spata','Welton Azevedo','Carlos Padrão','Camila Claro','Raphael Crespo','Yago Barbosa'
            )
            THEN 'BAROES'
        WHEN author_meta:display_name IN (
            'Adonai Marcondes','Laura Bernardes','Charles'
            )
            THEN 'HDD'
        ELSE author_meta:display_name
    END AS author_group,
    REGEXP_EXTRACT_ALL(tax_additional:tags:linked, '(?<=>)[^<]+(?=<\\/a>)',0) AS tags,
    REGEXP_EXTRACT_ALL(tax_additional:categories:linked, '(?<=>)[^<]+(?=<\\/a>)',0) AS categories,
    slug,
    title,
    acf_funnel,
    acf_user_type,
    DATEDIFF(dt_post_modified,dt_post_created) AS day_diff_create_modified,
    DATEDIFF(dt_post_modified,dt_post_created) > 90 AS has_changes_after_90_days,
    dt_post_created,
    dt_post_modified
FROM
    datalake_wordpress_baroes_clean.conteudos_data
QUALIFY 
    ROW_NUMBER() OVER(PARTITION BY id_post_wordpress ORDER BY dt_post_modified DESC) = 1