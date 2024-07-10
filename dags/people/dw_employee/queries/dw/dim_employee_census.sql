SELECT
    DISTINCT
    md5(
    concat(
      COALESCE(da.ethnicity, '-1'),
      COALESCE(da.gender_identity, '-1'),
      COALESCE(da.sexual_orientation, '-1'),
      COALESCE(da.neurodiversity, '-1'),
      COALESCE(da.religion,'-1'),
      COALESCE(da.country_situation, '-1'),
      COALESCE(da.housing_type, '-1'),
      COALESCE(da.quinto_andar_joining_method, '-1')
    )
  ) AS sk_employee_census, 
    COALESCE(da.ethnicity, '-1') AS ethnicity_code,
    CASE
      WHEN da.ethnicity IN ('1', '60', '7', 'ORA_HRX_BRIN') THEN 'Indígena'
      WHEN da.ethnicity = '2' THEN 'Branca'
      WHEN da.ethnicity IN ('3', '4', '15') THEN 'Preta'
      WHEN da.ethnicity IN ('6', '5') THEN 'Amarela'
      WHEN da.ethnicity IN ('8', 'ORA_HRX_MIXED', '20') THEN 'Parda'
      WHEN da.ethnicity = '9' THEN 'Prefiro Não Informar'
      ELSE '-1'
    END AS ethnicity_description,
    CASE
      WHEN da.gender_identity in (
        'Mulher cisgênero',
        'Cisgender woman',
        'Mujer Cisgénero (Cis)',
        'Mulher Cis'
      ) THEN 'mulher cisgenero'
      WHEN da.gender_identity in (
        'Mulher transgênero',
        'Transgender woman',
        'Mujer Transgénero (Trans)',
        'Mulher Trans ou Travesti'
      ) THEN 'mulher transgenero'
      WHEN da.gender_identity in (
        'Homem cisgênero',
        'Cisgender man',
        'Hombre Cisgénero (Cis)',
        'Homem Cis'
      ) THEN 'homem cisgenero'
      WHEN da.gender_identity in (
        'Homem transgênero',
        'Transgender man',
        'Hombre Transgénero (Trans)',
        'HomemTrans'
      ) THEN 'homem transgenero'
      WHEN da.gender_identity in (
        'Não-binário',
        'Non-binary',
        'Género no binario',
        'Gênero Não-binária'
      ) THEN 'nao-binario'
      WHEN da.gender_identity in (
        'Outro',
        'Other',
        'Otro',
        'Demi-genero',
        'Gênero Fluido',
        'Homem Trans Não-binário'
      ) THEN 'outro'
      WHEN da.gender_identity in (
        'Prefiro não informar',
        "I'd rather not answer",
        'Prefiero no responder'
      ) THEN 'prefiro nao informar'
      ELSE '-1'
    END AS gender_identity,
    CASE
      WHEN da.sexual_orientation IN ('1 - Assexual', 'Assexual', 'Asexual') THEN 'Assexual'
      WHEN da.sexual_orientation IN ('2 - Bissexual', 'Bissexual', 'Bisexual') THEN 'Bissexual'
      WHEN da.sexual_orientation IN (
        '3 - Heterossexual',
        'Heterossexual',
        'Heterosexual'
      ) THEN 'Heterossexual'
      WHEN da.sexual_orientation IN ('4 - Homossexual', 'Homossexual', 'Homosexual') THEN 'Homossexual'
      WHEN da.sexual_orientation IN ('5 - Pansexual', 'Panssexual', 'Pansexual') THEN 'Panssexual'
      WHEN da.sexual_orientation IN ('6 - Outro', 'Outro', 'Other', 'Otro') THEN 'Outro'
      WHEN da.sexual_orientation IN (
        '7 - Prefiro não informar',
        'Prefiro não informar',
        'Prefiero no responder'
      ) THEN 'Prefiro não informar'
      ELSE '-1'
    END AS sexual_orientation,
    COALESCE(da.neurodiversity, '-1') AS neurodiversity,
    CASE
      WHEN da.religion IN ('Agnosticismo', 'Agnosticism') THEN 'Agnosticismo'
      WHEN da.religion IN ('Ateísmo', 'Atheism') THEN 'Ateísmo'
      WHEN da.religion IN ('BUDDHIST', 'Budismo', 'Buddhism') THEN 'Budismo'
      WHEN da.religion = 'Candomblé' THEN 'Candomblé'
      WHEN da.religion IN (
        'ORA_HRX_CATHOLICISM',
        'Catolicismo',
        'Catholicism'
      ) THEN 'Catolicismo'
      WHEN da.religion IN ('HINDU', 'Hinduísmo', 'Hinduism') THEN 'Hinduísmo'
      WHEN da.religion IN ('Islã', 'Islam') THEN 'Islã'
      WHEN da.religion IN ('Jainismo', 'Jainism') THEN 'Jainismo'
      WHEN da.religion IN ('JEWISH', 'Judaísmo', 'Judaism') THEN 'Judaísmo'
      WHEN da.religion IN ('Mórmon', 'Mormon', 'Mormón') THEN 'Mórmon'
      WHEN da.religion IN (
        'Sem religião mas espiritualizado',
        'No religion but spiritual',
        'Esperitual pero sin religión'
      ) THEN 'Sem religião mas espiritualizado'
      WHEN da.religion IN ('Siquismo', 'Sikhism', 'Sijismo') THEN 'Siquismo'
      WHEN da.religion = 'Umbanda' THEN 'Umbanda'
      WHEN da.religion IN ('Zoroastrismo', 'Zoroastrianism') THEN 'Zoroastrismo'
      WHEN da.religion IN ('OTHER', 'Outro', 'Otro', 'Other') THEN 'Outra'
      WHEN da.religion IN (
        'NOTSTATED',
        'Prefiro não informar',
        "I'd rather not answer",
        'Prefiero no responder'
      ) THEN 'Prefiro Não Informar'
      WHEN da.religion = 'CHRISTIAN' THEN 'Cristianismo'
      WHEN da.religion IS NULL
      OR da.religion = 'NONE' THEN '-1'
      ELSE da.religion
    END AS religion,
    CASE
      WHEN da.country_situation IN ('Nativo(a)', 'Nativo', 'Native', 'Ciudadano') THEN 'Nativo'
      WHEN da.country_situation IN ('Refugiado', 'Refugee') THEN 'Refugiado'
      WHEN da.country_situation IN ('Imigrante', 'Immigrant') THEN 'Imigrante'
      WHEN da.country_situation IN ('Expatriado', 'Expatriate') THEN 'Expatriado'
      WHEN da.country_situation IN (
        'Prefiro não informar',
        "I'd rather not answer",
        'Prefiero no responder'
      ) THEN 'Prefiro não informar'
      ELSE '-1'
    END AS country_situation,
    CASE
      WHEN da.housing_type IN (
        'Imóvel alugado',
        'Rented property',
        'Propiedad alquilada'
      ) THEN 'Imóvel alugado'
      WHEN da.housing_type IN (
        'Imóvel de amigos ou parentes',
        'Property owned by friends or relatives',
        'Propiedad de amigos o familiares'
      ) THEN 'Imóvel de amigos ou parentes'
      WHEN da.housing_type IN (
        'Imóvel emprestado',
        'Borrowed property',
        'Propiedad prestada (no propia)'
      ) THEN 'Imóvel emprestado'
      WHEN da.housing_type IN (
        'Imóvel próprio financiado (sendo pago)',
        'Own property financed (being paid)',
        'Propiedad propia financiada (siendo pagada)'
      ) THEN 'Imóvel próprio financiado (sendo pago)'
      WHEN da.housing_type IN (
        'Imóvel próprio quitado',
        'Own property already paid off',
        'Propiedad propia (ya pagada)'
      ) THEN 'Imóvel próprio quitado'
      WHEN da.housing_type IN (
        'Pensão ou hotel',
        'Pension or hotel',
        'Pensión u hotel'
      ) THEN 'Pensão ou hotel'
      WHEN da.housing_type IN ('Outro', 'Other', 'Otro') THEN 'Outro'
      WHEN da.housing_type IN (
        'Prefiro não informar',
        "I'd rather not answer",
        'Prefiero no responder'
      ) THEN 'Prefiro não informar'
      ELSE '-1'
    END AS housing_type,
    CASE
      WHEN da.quinto_andar_joining_method IN (
        'Abordagem do time de People',
        'People team approach',
        'Selección desde el Equipo de People'
      ) THEN 'Abordagem do time de People'
      WHEN da.quinto_andar_joining_method IN (
        'Aquisição de outra empresa',
        'Acquisition of another company',
        'Adquisición de empresa por Grupo QuintoAndar'
      ) THEN 'Aquisição de outra empresa'
      WHEN da.quinto_andar_joining_method IN (
        'Candidatura direta',
        'Direct application',
        'Postulación a búsqueda abierta'
      ) THEN 'Candidatura direta'
      WHEN da.quinto_andar_joining_method IN (
        'Convite direto',
        'Direct invitation',
        'Hunting (contacto proactivo desde Grupo Quintoandar)'
      ) THEN 'Convite direto'
      WHEN da.quinto_andar_joining_method IN (
        'Indicação de alguém do time',
        'Recommendation from someone on the team',
        'Recomendación de un empleado/a de Grupo QuintoAndar'
      ) THEN 'Indicação de alguém do time'
      WHEN da.quinto_andar_joining_method IN (
        'Programa de empregabilidade',
        'Employability program',
        'Programa de acceso de empleo a minorías'
      ) THEN 'Programa de empregabilidade'
      WHEN da.quinto_andar_joining_method IN (
        'Sou um founder',
        "I'm a founder",
        'Soy fundador'
      ) THEN 'Sou um founder'
      WHEN da.quinto_andar_joining_method IN (
        'Prefiro não informar',
        "I'd rather not answer",
        'Prefiero no responder'
      ) THEN 'Prefiro não informar'
      ELSE '-1'
    END AS quinto_andar_joining_method,
    NOW() AS ts_load
  FROM
   datalake_hr_system.demographic_attributes AS da
  WHERE 
    GREATEST(DATE(ts_last_update), dt_effective_start) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')