select 
  a.agente_id,
  a.diaDaSemana,
  cast(from_unixtime(r.timestamp/1000) as date) as timestamp,
  horarios_disponivel08as09,
  horarios_disponivel09as10,
  horarios_disponivel10as11,
  horarios_disponivel11as12,
  horarios_disponivel12as13,
  horarios_disponivel13as14,
  horarios_disponivel14as15,
  horarios_disponivel15as16,
  horarios_disponivel16as17,
  horarios_disponivel17as18,
  horarios_disponivel18as19,
  horarios_disponivel19as20
from 
  HorarioSemanalAgente_AUD a

JOIN
  (
    select  
      ha.agente_id,
      ha.diaDaSemana,
      cast(from_unixtime(ra.timestamp/1000) as date) as t,
      max(ha.REV) as mRev
    FROM
      HorarioSemanalAgente_AUD ha
    join
      UsuarioRevisionEntity ra
      on ra.id = ha.REV
    -- where ha.agente_id = 120
    group BY
      ha.agente_id,
      ha.diaDaSemana,
      cast(from_unixtime(ra.timestamp/1000) as date)
  ) ur
  on ur.agente_id = a.agente_id
  and a.diaDaSemana = ur.diaDaSemana
  and a.REV = ur.mRev
join
  UsuarioRevisionEntity r
  on r.id = a.REV

 where   a.agente_id = 120;



  -- select * from HorarioSemanalAgente where agente_id = 120