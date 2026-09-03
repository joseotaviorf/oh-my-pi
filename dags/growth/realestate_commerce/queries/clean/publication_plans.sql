SELECT
    idplandepublicacion AS id_publication_plan,
    idTraduccion AS id_translation,
    idplandepublicacionsap AS id_sap_publication_plan,
    nombre AS publication_plan_name,
    peso AS plan_weight,
    esclonable AS is_cloneable
FROM
    datalake_realestate_raw.planesdepublicacion
