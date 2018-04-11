create or replace view v_Aquisicao as
select
  a.*,
  ai.imovel_id,
  au.usuario_id  
FROM
  Aquisicao a 
left join
   AquisicaoImovel ai
   on ai.id = a.id
left join
  AquisicaoUsuario au
  on au.id = a.id 


  