SELECT
    ID_Empresa_Site__c AS id_lead,
    CreatedDate AS creation_date,
    OwnerId AS id_analyst,
    CASE
        WHEN Ha_respondido_el_contacto__c = 'Si' THEN TRUE
        WHEN Ha_respondido_el_contacto__c = 'No' THEN FALSE
        ELSE FALSE
    END AS is_contacted,
    CASE
        WHEN Calificado__c = 'Si' THEN TRUE
        WHEN Calificado__c = 'No' THEN FALSE
        WHEN Calificado__c = 'No Aplica' THEN FALSE
        ELSE FALSE
    END AS is_qualified,
    CASE 
        WHEN Motivo_no_convierte__c = 'Duplicado' THEN 'DUPLICATED_LEAD'
        WHEN Motivo_no_convierte__c = 'Mala referencia del servicio' THEN 'OWNER_DIDNT_WANT_ADMINISTRATION'
        WHEN Motivo_no_convierte__c = 'Precio' THEN 'HOUSE_PRICE_WAS_OUT_OF_BOUNDS'
        WHEN Motivo_no_convierte__c = 'Prospecto no responde' THEN 'OWNER_DIDNT_ANSWER_PHONE'
        WHEN Motivo_no_convierte__c = 'Satisfecho con la competencia' THEN 'OWNER_DIDNT_WANT_ADMINISTRATION'
        WHEN Motivo_no_convierte__c = 'Sin presupuesto' THEN 'HOUSE_PRICE_WAS_OUT_OF_BOUNDS'
        WHEN Motivo_no_convierte__c = 'Sin propiedades' THEN 'CONTACT_WASNT_THE_HOUSE_OWNER'
        WHEN Motivo_no_convierte__c = 'No califica' THEN 'OWNER_DIDNT_SELECT_CONTEXT'
        WHEN Motivo_no_convierte__c = 'Descartado' THEN 'OWNER_GAVE_UP_RENTING'
        WHEN Motivo_no_convierte__c = 'Datos de contacto erróneo' THEN 'CONTACT_DIDNT_EXIST'
        WHEN Motivo_no_convierte__c = 'Fuera del negocio' THEN 'HOUSE_WAS_OUT_OF_HOUSE_RENTING_REGIONS'
        WHEN Motivo_no_convierte__c = 'Alquiler por temporada (fuera del modelo)' THEN 'SEASONAL_RENT'
        WHEN Motivo_no_convierte__c = 'Contacto inexistente' THEN 'CONTACT_DIDNT_EXIST'
        WHEN Motivo_no_convierte__c = 'Contrato de exclusividad' THEN 'HOUSE_UNDER_EXCLUSIVITY_CONTRACT'
        WHEN Motivo_no_convierte__c = 'El contacto es inmobiliaria/corredor (teléfono incorrecto)' THEN 'CONTACT_WAS_FROM_REAL_ESTATE_BROKER_OR_AGENT'
        WHEN Motivo_no_convierte__c = 'El contacto no es propietario (teléfono incorrecto)' THEN 'CONTACT_WASNT_THE_HOUSE_OWNER'
        WHEN Motivo_no_convierte__c = 'El teléfono no responde' THEN 'OWNER_DIDNT_ANSWER_PHONE'
        WHEN Motivo_no_convierte__c = 'Estructura precaria (fuera del modelo)' THEN 'HOUSE_WITH_BAD_CONDITIONS'
        WHEN Motivo_no_convierte__c = 'Inmueble comercial (fuera del modelo)' THEN 'HOUSE_WAS_A_BUSINESS_REAL_ESTATE'
        WHEN Motivo_no_convierte__c = 'Inmueble con problemas en la documentación' THEN 'ISSUES_WITH_HOUSE_DOCUMENTATION'
        WHEN Motivo_no_convierte__c = 'Inmueble en planos o terreno (fuera del modelo)' THEN 'PROPERTY_IN_OFFPLANT'
        WHEN Motivo_no_convierte__c = 'Inmueble en reforma por más de 3 meses' THEN 'HOUSE_UNDER_MAJOR_RENOVATION'
        WHEN Motivo_no_convierte__c = 'Inmueble no disponible por más de 3 meses' THEN 'HOUSE_ALREADY_RENTED_FOR_MORE_THAN_3_MONTHS'
        WHEN Motivo_no_convierte__c = 'Inmueble ya publicado en 5Andar' THEN 'HOUSE_ALREADY_PUBLISHED'
        WHEN Motivo_no_convierte__c = 'No acepta administrador (rechazo pp)' THEN 'OWNER_DIDNT_WANT_ADMINISTRATION'
        WHEN Motivo_no_convierte__c = 'No acepta comisión de corretaje (rechazo pp)' THEN 'OWNER_CONSIDERED_BROKERAGE_FEE_TOO_HIGH'
        WHEN Motivo_no_convierte__c = 'No acepta tarifa de administración mensual (rechazo pp)' THEN 'OWNER_CONSIDERED_ADMINISTRATION_FEE_TOO_HIGH'
        WHEN Motivo_no_convierte__c = 'No desea recibir conexión (rechazo pp - lista de bloqueo)' THEN 'CONTACT_ON_BLOCK_LIST'
        WHEN Motivo_no_convierte__c = 'No está de acuerdo con el pago de algunos cargos (rechazo propietario)' THEN 'OWNER_DISAGREE_CHARGES_PAYMENTS'
        WHEN Motivo_no_convierte__c = 'No hay interés en vender (rechazo pp)' THEN 'OWNER_GAVE_UP_SELLING'
        WHEN Motivo_no_convierte__c = 'No mapeado' THEN 'HOUSE_WAS_OUT_OF_HOUSE_RENTING_REGIONS'
        WHEN Motivo_no_convierte__c = 'No quería escuchar la propuesta (rechazo pp)' THEN 'OWNER_DIDNT_LISTEN_TO_PITCH'
        WHEN Motivo_no_convierte__c = 'Problemas para acceder al inmueble – Llaves o indisponibilidad' THEN 'ISSUES_WITH_HOUSE_ENTRANCE_CONDITIONS'
        WHEN Motivo_no_convierte__c = 'Propiedad en inventario' THEN 'PROPERTY_IN_JUDICIAL_INVENTORY'
        WHEN Motivo_no_convierte__c = 'Propiedad solo en venta' THEN 'HOUSE_ONLY_FOR_SELLING'
        WHEN Motivo_no_convierte__c = 'Propietario con indisponibilidad de agenda' THEN 'OWNER_UNAVAILABLE_SCHEDULE'
        WHEN Motivo_no_convierte__c = 'Rango de precio por encima/debajo (fuera del modelo)' THEN 'HOUSE_PRICE_WAS_OUT_OF_BOUNDS'
        WHEN Motivo_no_convierte__c = 'Sala para alquiler (fuera del modelo)' THEN 'ONLY_PART_OF_THE_HOUSE_WAS_AVAILABLE_FOR_RENTING'
        WHEN Motivo_no_convierte__c = 'Servicio Prime' THEN 'OWNER_WITH_PRIME_PROFILE'
        WHEN Motivo_no_convierte__c = 'Sin interés en alquilar (rechazo pp)' THEN 'OWNER_GAVE_UP_RENTING'
        WHEN Motivo_no_convierte__c = 'Descartado sin contacto' THEN 'OWNER_DIDNT_ANSWER_PHONE'
        ELSE NULL
    END AS discard_reason,
    Phone AS phone,
    Direccion__c AS address,
    Canal__c AS channel,
    Id AS id_salesforce,
    Status AS status,
    LastName AS owner_name,
    RecordTypeId AS record_type_id,
    dt_updated,
    year,
    month,
    day
FROM
    datalake_salesforce_growth_raw.lead
WHERE
    MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')