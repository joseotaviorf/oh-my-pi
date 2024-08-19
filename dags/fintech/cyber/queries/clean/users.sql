SELECT
    CLCOLLID AS id_user,
    CLSSNUM AS id_unique_user,
    CLLDAPID AS id_ldap,
    CLAGENCY AS agency,
    CLRTYPE AS record_type,
    CASE
        WHEN CLCTYPE = 1 THEN "Auxiliar"
        WHEN CLCTYPE = 2 THEN "Gestor"
        WHEN CLCTYPE = 3 THEN "Supervisor"
        ELSE CLCTYPE
    END AS manager_type,
    CASE
        WHEN CLUTYPE = 1 THEN "Interno"
        WHEN CLUTYPE = 2 THEN "Externo."
    ELSE CLUTYPE
    END AS user_type,
    CASE
        WHEN CLMODE = "T" THEN "Em trenamento"
        ELSE CLMODE
    END AS administer_mode,
    CLSUPV AS supervisor,
    CLPROF AS user_profile,
    CLSECS AS time_inactivity,
    CLSTATUS AS password_status,
    CLNAME AS name,
    CLPASSWD AS password,
    CLMAIL AS email,
    CLPHONE AS phone,
    CLEXT AS phone_extension,
    CLDEPT AS department,
    CLNIVEL AS level,
    CLTITLE AS title,
    CLSALCD AS greeting,
    CASE
        WHEN CLLTYPE = 11 THEN "Auxiliar legal"
        WHEN CLLTYPE = 12 THEN "Advogado"
        WHEN CLLTYPE = 12 THEN "Advogado supervisor"
        ELSE CLLTYPE
    END AS type_legal,
    IF(CLGROUP="Y", TRUE, FALSE) AS has_permission_review_another_supervisor,
    CLPRINT AS printer,
    CLENABLED,
    CLLSTACSDT,
    CLLNG,
    CLLAT,
    CLRONLY,
    CLCREUSER,
    CLCHGUSER
FROM datalake_cyber_raw.collid
