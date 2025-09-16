SELECT
  id_region_match_operation_city,
  id_region_match_operation_neighborhood,
  dt_created,
  keyword,
  keyword_clean,

  CASE WHEN match_igbe_city = '' THEN ''
    WHEN keyword_clean REGEXP 'bh|carapicuiba|goiania|nova iguacu|santo andre|sao bernardo do campo|sao caetano|sao goncalo|sao paulo|sbc|sjc|visconde de maua| sbo| vcp| vix| rj| sp|rj |sp ' THEN match_igbe_city
    WHEN RLIKE(keyword_clean, r'.*(\bsp\b).*') THEN COALESCE(match_igbe_city, 'sao paulo')
    WHEN RLIKE(keyword_clean, r'.*(\brj\b).*') THEN COALESCE(match_igbe_city, 'rio de janeiro')
    WHEN keyword_clean like '% ' || match_igbe_city || ' %' THEN match_igbe_city 
    WHEN keyword_clean like match_igbe_city || ' %' THEN match_igbe_city 
    WHEN keyword_clean like '% ' || match_igbe_city THEN match_igbe_city
    WHEN keyword_clean like match_igbe_city THEN match_igbe_city
    ELSE ''
  END as match_igbe_city,

  CASE WHEN match_operation_city = '' THEN ''
    WHEN keyword_clean REGEXP 'bh|carapicuiba|goiania|nova iguacu|santo andre|sao bernardo do campo|sao caetano|sao goncalo|sao paulo|sbc|sjc|visconde de maua| sbo| vcp| vix| rj| sp|rj |sp ' THEN match_operation_city
    WHEN RLIKE(keyword_clean, r'.*(\bsp\b).*') THEN match_operation_city
    WHEN RLIKE(keyword_clean, r'.*(\brj\b).*') THEN match_operation_city
    WHEN keyword_clean like '% ' || match_operation_city || ' %' THEN match_operation_city 
    WHEN keyword_clean like match_operation_city || ' %' THEN match_operation_city 
    WHEN keyword_clean like '% ' || match_operation_city THEN match_operation_city
    WHEN keyword_clean like match_operation_city THEN match_operation_city
    ELSE ''
  END as match_operation_city,

  CASE WHEN match_operation_neighborhood = '' THEN ''
  WHEN keyword_clean like '% ' || match_operation_neighborhood || ' %' THEN match_operation_neighborhood 
  WHEN keyword_clean like match_operation_neighborhood || ' %' THEN match_operation_neighborhood 
  WHEN keyword_clean like '% ' || match_operation_neighborhood THEN match_operation_neighborhood
  WHEN keyword_clean like match_operation_neighborhood THEN match_operation_neighborhood
  ELSE ''
  END as match_operation_neighborhood,
  
  page, 
  google_property,
  branded,
  page_cluster,
  structure,
  page_structure,
  page_path,
  state,
  city,
  location_level,
  search_region,
  poi_type,
  filter_count,
  filter_combination,
  position,
  impressions,
  clicks,
  ctr,
  posimp,
  site_url,
  device,
  domain,
  slug,
  subtitle_content,
  is_branded,
  is_goldenset,
  has_mention_to_location,

  CASE
    WHEN CONTAINS(keyword_clean, 'ipca 20') THEN 0
    WHEN keyword_clean REGEXP 'bh|carapicuiba|goiania|nova iguacu|santo andre|sao bernardo do campo|sao caetano|sao goncalo|sao paulo|sbc|sjc|visconde de maua| sbo| vcp| vix| rj| sp|rj |sp ' THEN 1
    WHEN keyword_clean REGEXP 'barcelona|berlim|boston|bruxelas|cascais|frankfurt|lisboa|londres|los angeles|madri |miami|nova york|orlando|paris|san francisco' THEN 1
    WHEN RLIKE(keyword_clean, r'.*(\bsp\b).*') THEN 1
    WHEN RLIKE(keyword_clean, r'.*(\brj\b).*') THEN 1
    WHEN (match_igbe_city LIKE '' AND match_operation_city LIKE '') THEN 0
    WHEN (match_igbe_city NOT LIKE '' AND keyword_clean LIKE '% ' || match_igbe_city || ' %') THEN 1 
    WHEN (match_igbe_city NOT LIKE '' AND keyword_clean LIKE match_igbe_city || ' %') THEN 1 
    WHEN (match_igbe_city NOT LIKE '' AND keyword_clean LIKE '% ' || match_igbe_city) THEN 1
    WHEN (match_igbe_city NOT LIKE '' AND keyword_clean LIKE match_igbe_city) THEN 1
    WHEN (match_operation_city NOT LIKE '' AND keyword_clean LIKE '% ' || match_operation_city || ' %') THEN 1 
    WHEN (match_operation_city NOT LIKE '' AND keyword_clean LIKE match_operation_city || ' %') THEN 1 
    WHEN (match_operation_city NOT LIKE '' AND keyword_clean LIKE '% ' || match_operation_city) THEN 1
    WHEN (match_operation_city NOT LIKE '' AND keyword_clean LIKE match_operation_city) THEN 1
    ELSE 0
  END AS has_mention_to_city,

  CASE
    WHEN CONTAINS(keyword_clean, 'ipca 20') THEN 0
    WHEN keyword_clean REGEXP 'bairro|jd |veredas|village ' THEN 1
    WHEN match_operation_neighborhood LIKE '' THEN 0
    WHEN keyword_clean LIKE '% ' || match_operation_neighborhood || ' %' THEN 1 
    WHEN keyword_clean LIKE match_operation_neighborhood || ' %' THEN 1 
    WHEN keyword_clean LIKE '% ' || match_operation_neighborhood THEN 1
    WHEN keyword_clean LIKE match_operation_neighborhood THEN 1
    ELSE 0
  END AS has_mention_to_neighborhood,

  CASE
    WHEN CONTAINS(keyword_clean, 'ipca 20') THEN 0
    WHEN keyword_clean REGEXP 'cep ' THEN 1
    WHEN keyword_clean REGEXP '[0-9][0-9][0-9][0-9][0-9]-[0-9][0-9][0-9]' THEN 1 
    WHEN keyword_clean REGEXP '[0-9][0-9][0-9][0-9][0-9] [0-9][0-9][0-9]' THEN 1 
    WHEN keyword_clean REGEXP '[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]' THEN 1 
    ELSE 0 
  END AS has_mention_to_cep,

  CASE
    WHEN CONTAINS(keyword_clean, 'ipca 20') THEN 0
    WHEN keyword_clean REGEXP 'regiao|regioes|zona' THEN 1
    ELSE 0 
  END AS has_mention_to_city_zone,

  CASE
    WHEN keyword_clean REGEXP 'corretor|direto com dono|direto com o dono|direto com o proprietario|direto com proprietario|proprietario|proprietario direto|proprietariodireto' THEN 1
    ELSE 0 
  END AS has_mention_to_agent,

  CASE
    WHEN keyword_clean REGEXP 'ape11|ape 11' THEN 0
    WHEN keyword_clean LIKE 'ap %' THEN 1
    WHEN keyword_clean LIKE 'ape %' THEN 1 
    WHEN keyword_clean REGEXP ' ap |apart|apartamento|apartamento cobertura| ape |apt|apt |apto|cobertura|conjugado|duplex|flat|maxhaus|studio|triplex' THEN 1
    ELSE 0 
  END AS has_mention_to_apartment,

  CASE
    WHEN keyword_clean REGEXP 'alo negocios|aluga mais|aluga max|alugamais|alugamax|bona imoveis|brasil brokers|brognoli|caixa imoveis|classificados|claudino imoveis|coelho da fonseca|credpago|imobiliaria|livima imoveis|netimoveis|plano e plano|proprietarios imoveis|silverio imoveis|agente imovel|arbo imoveis|arboimoveis|arbo |mgf imoveis|mgfimoveis|mgf |bridge imoveis| bridgeimoveis|net imoveis|netimoveis|attria' THEN 1
    WHEN keyword_clean LIKE 'imoveis em %' THEN 0
    WHEN keyword_clean LIKE '%aluguel de imoveis%' THEN 0
    WHEN keyword_clean LIKE '%aluguel imoveis%' THEN 0
    WHEN keyword_clean LIKE '%alugar imoveis%' THEN 0
    WHEN keyword_clean LIKE '%venda de imoveis%' THEN 0
    WHEN keyword_clean LIKE '%venda imoveis%' THEN 0
    WHEN keyword_clean LIKE '%vendas imoveis%' THEN 0
    WHEN keyword_clean LIKE '%vendas de imoveis%' THEN 0
    WHEN keyword_clean LIKE '%compra de imoveis%' THEN 0
    WHEN keyword_clean LIKE '%compras de imoveis%' THEN 0
    WHEN keyword_clean LIKE '%compre imoveis%' THEN 0
    WHEN keyword_clean LIKE '%compra imoveis%' THEN 0
    WHEN keyword_clean LIKE '%comprar imoveis%' THEN 0
    WHEN keyword_clean REGEXP ' imoveis' THEN 1
    ELSE 0 
  END AS has_mention_to_brokerage,

  CASE
    WHEN keyword_clean REGEXP 'auxiliadora predial' THEN 0
    WHEN keyword_clean REGEXP 'administradora|auxiliadora|bradesco|empreendimento|engenharia|incorporador|incorporadora' THEN 1
    ELSE 0 
  END AS has_mention_to_company,

  CASE
    WHEN keyword_clean LIKE '% condo' THEN 1
    WHEN keyword_clean LIKE 'condo %' THEN 1
    WHEN keyword_clean LIKE 'ed %' THEN 1
    WHEN keyword_clean REGEXP 'cond |condominio|conj |conjunto|copan| ed |edificio|em um condominio |em um edificio |em um predio |guarita|predio|residencial' THEN 1
    WHEN keyword_clean LIKE '%alphaville%' THEN 0
    WHEN keyword_clean REGEXP 'spazio|ville|vn ' THEN 1
    ELSE 0 
  END AS has_mention_to_condo,

  CASE
    WHEN keyword_clean REGEXP '24 horas|24 hrs|24 hs|24h |academia |acesso sem degraus|bicicletario|brinquedoteca|churrasqueira no condominio|corrimao |elevador |energia |espaco gourmet|espaco para churrasco |garagem |garagem fixa|perto do metro|piscina no condominio|playground|portao automatico|portaria |porteiro |proximo metro|quadra esportiva|rampas de acesso|rua silenciosa|salao de festas|salao de jogos|sauna |somente uma casa terreno|vaga |vaga de garagem acessivel' THEN 1
    ELSE 0 
  END AS has_mention_to_condo_facilities,

  CASE
    WHEN keyword_clean REGEXP 'casa e construcoes|casa e construcao' THEN 0
    WHEN keyword_clean REGEXP 'construcao|construcoes|construtora|cyrela|mrv |tenda ' THEN 1
    ELSE 0 
  END AS has_mention_to_construction,

  CASE
    WHEN CONTAINS(keyword_clean, 'ipca 20') THEN 0
    WHEN keyword_clean REGEXP ' eua |alemanha|argentina|belgica|brasil |brazil |canada|colombia|espanha|estados unidos|franca|inglaterra|italia |mexico|portugal|uruguai' THEN 1
    ELSE 0 
  END AS has_mention_to_country,

  CASE
    WHEN keyword_clean REGEXP 'sala comercial|salas comerciais|area gourmet|varanda gourmet|espaco gourmet' THEN 0
    WHEN keyword_clean REGEXP 'abajur|acabamento|acaros|acustico|adega |adubo|almofada|ana hickmann|aparador|aquario|aquecedor|armarios|arquitetura|arranjo para|arranjos de flores|arrumacao|arrumando|arrumar|art |artesanato|artistas|arvore de natal|arvore para |arvore para dentro de |arvores para|arvorismo|as casas mais|as mansoes mais|aspirador|azulejo|banheira|beyonce|biombo|blindex|bonsai|borda de piscina|box|bruna linzmeyer|cabeceira|cacto|cactos|cadeira|cadeiras|cafeteira|cama |cama de casal|cama de solteiro|cantinho|canto do cafe|caracteristicas|casa feita com|casa madeira|casinha de madeira|churrasco|chuveiro|clarice lispector|coifa|com entrada|com vista|combinacao|conceito aberto|cooktop|cor |cores |corredor|cortina|cortinas|cortinas black out|cortinas decorativas|cozinha|cozinha americana|cristaleira|cristaleiras|cristiano ronaldo|de madeira|deck |decks|decoracao|decorado|decorar|detergente|eletrodomestico|eletrodomesticos|elvis presley|elza soares|espelho no banheiro|estilo|fachada |fachadas |famosos|festa junina|fogao |fogao geladeira|forno|foto de |fotos|fotos |frente de casa|frigobar|geladeira|geminada|geminado|gesso|gourmet|hall |hall de entrada|halloween|horta|horta vertical|iluminacao|iluminar|imagem|imagens|infantil|inspiracao|janela|jardim de inverno|jogo de cama|jogo de casal|jogo de cozinha|lareira|lava e seca|lavabo|lavanderia|lionel messi|lounge|lucas rangel|luminaria|lustre|marilyn monroe|mark zuckenberg|mesa|mesa |mesas|mesas |mesas e cadeiras de escritorio|mesas e cadeiras jantar|mezanino|microondas|minimalistas|moldura|moveis planejados|neymar|organizacao|organizando|paisagens |paisagem|paisagismo|papel de parede|parede|pe direito|pia |pintura|piso |piso laminado|piso porcelanato|piso queimado|piso tatil|pisos |planta |planta baixa |plantas|pre fabricada|pre montada|premoldada|purificador|ralo |rede de protecao|reforma|renato russo|ronaldinho|rubinho barrichelo|sala |salas |selena gomez|sem paredes|sofa|sossego|suculentas|tapete|televisao|tvs |tv |utensilios de cozinha|walt disney| mesa | mesas ' THEN 1
    ELSE 0 
  END AS has_mention_to_decor,

  CASE
    WHEN keyword_clean REGEXP '0lx|casa mineira|chaves na mao|chave na mao|imovel na web|imovel web|imovelweb|mercado livre|mitula|olx|olx imoveis|trovit|viva real|vivareal|vivreal|wimov|wimoveis|zap' THEN 1
    ELSE 0 
  END AS has_mention_to_e_classified,

  CASE
    WHEN keyword_clean REGEXP 'amapa' THEN 0
    WHEN keyword_clean LIKE 'dica %' THEN 1
    WHEN keyword_clean LIKE 'facil %' THEN 1
    WHEN keyword_clean LIKE 'fazer %' THEN 1
    WHEN keyword_clean LIKE 'onde %' THEN 1
    WHEN keyword_clean LIKE 'mais %' THEN 1
    WHEN keyword_clean LIKE 'dicas %' THEN 1
    WHEN keyword_clean LIKE 'morar %' THEN 1
    WHEN keyword_clean REGEXP 'assalto|atividades|bairros com|bairros em|bairros mais|bairros nobres|barulho|bem barato|boa convivencia|cidades d|cidades vizinhas|coisas para fazer|colocar|construcard|construir|copasa|coworking|cptm|cuidar |cultura|custo de vida| dica | dicas |diferenca|do mundo|faca voce mesmo| facil | fazer |habite|indicar|indique|juntar|lugares |maior |maiores | mais |mais alto|mais assombrada|mais bonita|mais cara|mais caras|mais desenvolvidas|mais linda|mais populosas|mais recentes|mais seguras|mapa |medida|melhor |melhores| morar |na roca| onde |passo a passo|pedir |perturbacao|sabesp|seguranca |simples|sindico|sindico |sugestoes|escolas particulares' THEN 1
    ELSE 0 
  END AS has_mention_to_guide_tips,

  CASE
    WHEN keyword_clean REGEXP 'ate que horas|cola para|com o que|com quantas|com quantos|com que|como |como fazer|como funciona |compensa|funciona | funciona|horario de silencio|o que |o que fazer|para que|perdi |porque|posso |quais |qualquer |qual |quando |quantos |quanto |quanto tempo|quem |a partir de qual|a partir de quanto|a partir de que|quantas |como tirar|como calcular' THEN 1
    ELSE 0 
  END AS has_mention_to_helps_doubts,

  CASE
    WHEN keyword_clean REGEXP 'casa mineira|wimovel|imovelweb|imovel web| zap imovel' THEN 0
    WHEN keyword_clean REGEXP 'webimovel|imovelguide|imovel guide' THEN 0
    WHEN keyword_clean REGEXP '123 imovel|emcasa|dream casa|tuacasa|casa e construcao|casa abril|casa vogue' THEN 0
    WHEN keyword_clean REGEXP 'casa|casas|imovel|mansao|mansoes|residencia |sobrado' THEN 1
    ELSE 0 
  END AS has_mention_to_house_type,

  CASE
    WHEN keyword_clean REGEXP 'animais |animais de estimacao|animal |ar condicionado|area comum |area de lavar|area de lazer|area de servico|area de tanque|area externa|area gourmet|area verde|armario|armarios na cozinha|armarios no banheiro|armarios no quarto| ate |bancada|banheiro|banheiro adaptado|banheiro de servico|barato|biblioteca|cachorro|churrasq|churrasqueira|churrasqueira privativa|chuveiro a gas|chuveiro eletrico|closet|com mobilia|comodo |comodos|deck|dormit|dormitorios|edicula |ediculas|escritorio|fechadura eletronica|gas encanado| gato |hidromassagem|internet |janela anti ruido|luminosidade natural| m2 |maquina de lavar| mil |mobiliada |mobiliado |mobiliados |mobiliadas |pet |piscina|piscina |piscina privativa|quartos |quarto |quarto de servico|quarto extra reversivel|quartos corredores portas amplas|quato |quintal |reais |sala de jantar|secadora|sol da manha|sol da tarde|tanque|tomadas novas|varal |varal de roupas|varanda|varanda gourmet|ventilador|ventilador de teto|vista livre' THEN 1
    ELSE 0 
  END AS has_mention_to_house_facilities,

  CASE
    WHEN keyword_clean REGEXP 'kitchennete|kitinete|kitinetes|kitnet|quitinete|kit net |kit net|kitinet' THEN 1
    ELSE 0 
  END AS has_mention_to_kitnet,

  CASE
    WHEN keyword_clean REGEXP 'porto seguro' THEN 0
    WHEN keyword_clean REGEXP 'benfeitorias|comgas|crises |crise |crise imobiliaria|custo |economica|edp |fgts|idh |igp |igpm|imposto|imposto de renda|indice|indice |inflacao|investimento|investir|ipca|ipca 20|iptu | ir |isencao |itbi|juros|laudo|lei |lei do inquilinato|leis |lucro |marketplace|porcentagem|preco|preco |precos|previsao|price|queda|seguro |tabela|taxas |taxa |tendencia|enel segunda via|titularidade' THEN 1
    ELSE 0 
  END AS has_mention_to_law_taxes_market,

  CASE
    WHEN keyword_clean REGEXP 'campo grande|praia grande|campina grande|varzea grande|rio grande do norte|rio grande do sul|rio grande' THEN 0
    WHEN keyword_clean REGEXP 'ajustar|baratinha|bom para|caseiro|consertar|concertar|cuidado|desentupir|grande|ideias de|ideias para|infiltracao|pensao|permuta|reparar|limpar' THEN 1
    ELSE 0 
  END AS has_mention_to_life_hack,

  CASE
    WHEN keyword_clean LIKE 'casas para alugar%' THEN 0
    WHEN keyword_clean LIKE '%chaves na mao%' THEN 0
    WHEN keyword_clean LIKE '%chave na mao%' THEN 0
    WHEN keyword_clean LIKE '%quinto andar%' THEN 0
    WHEN keyword_clean LIKE '%quintoandar%' THEN 0
    WHEN keyword_clean LIKE '%av brigadeiro%' THEN 0
    WHEN keyword_clean LIKE '%kit net%' THEN 0
    WHEN keyword_clean REGEXP 'condominio|residencial|edificio|apartamento|imovel|imoveis| casa | casas |5 andar telefone' THEN 0
    WHEN keyword_clean REGEXP 'como tirar adesivo de vidro|como desentupir pia de cozinha|como calcular metro quadrado|troca de titularidade sabesp|sabesp transferência de titularidade|como limpar ferro de passar roupa|separação total de bens|desentupir pia da cozinha|tipos de moradia|escolas particulares|desentupir pia da cozinha|registro de imove' THEN 0

    WHEN keyword_clean LIKE 'fipe' THEN 1
    WHEN keyword_clean REGEXP '1113|1513|1620|1634|23220|24250|2 via|2a via|2o via|4x4|abafador de som|acai |acampamento|acaraje|acessorios|acidente |acompanhante|acougue|adaptacao|adesivo|advogado|aeroclube|aerofolio|aeronautas|agencia|agronomia|agropecuraria|agropop|aircross|alambique|alargador|alfa romeo|alienacao|altura|altura |aluguel de beca|aluguel de malas|aluguel de mesas e cadeiras|aluminio|amarok|ambev|ambulancia|american pet|americanas|amiga|amigo|amil espaco saude|amoedo |amortecedor|analista comercial|aniversario|antena parabolica|antes e depois|antiquario|aplicacao|apoio administradora|aqua park|aqua parque|aquamundi|aquaparque|aranha|arara |arco e flecha|arezzo|aromatizador|arquiteto|arrependimento|artigos|arvore|asilo|assai atacadista|assembleia |astra |asx|asx |atacadao|atacadista|atacado |atelier|atendente|atendimento|audi |aula de |aulas de|auto escola|auto pecas|autoclave|autodromo|automotivo|automoveis|automovel|autonomia|autorizacao|autorizada|auxiliar de |avental|aves |avestruz|aviao|azera|baba |bacalhau|bacon |bahamas|bakery|balada |baladas |balao|balcao|bananal|bananas|banco|banco central|bandeira|bandeira |bangalo|banho e tosa|barbearia|barco|barraca|barracos| bau |bazar|beach park|bebedouro|bebidas|beetie|berco|bicarbonato |bicicletas|bico de|bico em|bicos de|bicos em|bike|biomedicina|biz |blazer|blindado|blindagem|blog|blog |bmw|boate |boates|boi |boliche|bolo de |bolsa de' THEN 1  
    
    WHEN keyword_clean REGEXP 'bombinhas| botas|botequim|boutique|brasileiro|brastemp|brecho|brigadeiro|brincadeira|brinquedo|brinquedos|brumado|buffet|buggy|burguer|burguer king|c&c|c10|c14|c20|c3|cabeleireiro|cabine |cabrito|cacamba|cacatua|cacau show|cachimbo|cadeira de rodas|caiaque|caixa economica|caixa para|calopsita|camacari|camara fria|camara frigorifica|cambio |cambio automatico|camelodromo|cameras|cameras ao vivo|caminhao|caminhoes|caminhonete|camioneta|camper |camping|canjica|canoa usada|caoa chery|capa de croche|capa para|capota de fibra|capota maritima|captiva|captur|caravan|caravan |carburador |cardillac|carreta |carretinha|carro|carroceria|carta |cartao de todos|cartao de visita|carteira de corretor|casa e video|casais|casal|casamento|casas bahia|casinha para|cassino|castos|cavalo|cb 1000|cb 300|cb 500|cbr|cbr |cbs|cdhu|cedae|celta |celular|cemig|cemiterio|centauro|central de atendimento|central de negocios|central de repasse|central de vagas|central multimidia|centro administrativo|centro de compras|ceramica|certidoes|cervejaria|chamonix|chapelaria|chapeu|chapeus|chassi |chave |chaveiro |check list|cherokee|chery|chevette|chevrolet|chevy|china in box' THEN 1  
    
    WHEN keyword_clean REGEXP 'chopeira|choperia|chopp|chrysler|cimento|cine |cineplex|cinepolis|cineroxy|citroen|civic|clarear|classic|classinesia|clausula |cleanic|clio |cobalt|coca cola|coelho|cofre|cofre escondido|coisas|colchoes|coleiro|coletiva|coletor|colocacao colegios|colocacao de drywall|colocacao de piso|colocacao escolas|colonia agricola|colonia de ferias|comida|comissao|compreauto|comprecar |compressor|computador|comunicado|concessionaria|concordia|concreto usinado|confeitaria|congregacao|conselho fiscal|consorcio|consultor | conta |conta corrente|controlador|conversa|conversivel|convocacao|convocatoria |coooperativa|cooper|copiadora|corcel|corolla|corsa|corsa |cortador|coruja|costureira|country club|courier|coxinha|cpf|cpfl|creta|creta |crf |croasonho|cronograma|crossfit|crossfox|cruz vermelha|cruze |cruzeiro|crv |ct |cta |ctg|cuidador |curso |curso corretor|curso de corretor|d 20|d10|d20|de repouso|de show|delicatessen|desenho|desmembramento|detalhamento|detalhe| dia |dia a dia|dia d|diplomata|distribuicao|divida|divisao|divisoria|divorcio|doacao|doacao |doblo|dodge|ducato|duster|ecosport|elantra|em espanhol|em frances|em ingles' THEN 1  
    
    WHEN keyword_clean REGEXP 'emprego|empresa|empresas |enfeite|entrada de |entrega |entrevista|entupimento|enxoval|equipamento|escada|escadas|escarpas|escavadeira|escort|escravo|espelho com fita|espelho com led|esquadria|estacionamento|estadia|esteira|estrutura | etios|exemplo|f 100|f 1000|f 250|f 350|f 4000|f100|f1000|f250|f350|f4000|f75|fabrica|faculdade corretor|faculdade para corretor|falcon|familia|fantasia|fantasias|feira de imoveis|feirao de imoveis|ferramenta|festa|fiat|fiat freemont|fiesta|filho |filme |fiorino|fita de led |focus |fogueira|folhagem|food truck|ford |formigas|forno de pizza|fotografia|fox |fraldas|franquia|frase |frases |freezer|fritadeira eletrica|frontier|fusca|fusion|futebol|gabinete|gado |gaiola|galeria|garagem para alugar|gerador|gol |golf|grafica|grama |granjas|grupo|guarda roupa|guarda sol|guincho|gurgel|halteres|haras|hb20|helbor|heliponto|herdeiro|hilux|honda|hornet|hr |hrv |i30|ingrediente|ingredientes|interfone|inveja|inventario|iphone|isolamento| itau|jaguar |jantar |jeep|jequile|jet ski|jetta|jogo|jogo de |jogo de perguntas|jogos|joias|jornal|kadett|kangoo|karaoke|kia |kombi|l200|labrador|lamborghini|lan house|lancer |lancha|lanchonete|lava jato|lava rapido' THEN 1
    
    WHEN keyword_clean REGEXP 'legislar|leilao|leiloes|limosine|limpeza| lista |listagem|livros|logan |loja de moveis|loja do|lojas americanas|lontra|loterica|loucas|macaco|malas|maleiro|manequim|manteiga|maquina|marido|mariscos|masseira|maverick|medicina diagnostica|megafone| mei |memorial |mensagem de |mensagem para|mercado de imoveis|mercedes|meriva|milho|modelos de |mohave|molas esportivas|molde|monza |morango|motel| moto |motorhome|motos|motos |mp lafer|muletas|muro|mustang|namorada|namorado|navio| net |new fiesta|nirf|nissan|normas para|notebook|nozes |numerologia|objetos|obras |oficina|onix|onix |opala |ordenhadeira|organizadores|outlet|ovelhas|pajero|paleta |paletes|palio|panelas|papagaio|papel|papelao|papelaria|particulares|partilha|passarinho|passaros|passat |patins|pecas|pedido|pedido de ligacao|pequenas empresas grandes negocios|perfil de led|periquitos|permuta de |pernilongos|perucas|pesca|pesque pague|pesqueiro|pesquisa de |pessoas|peugeot| pia | pias |picape|pick up|ping pong|pisca pisca|pizza|pizzaria|placas|png|poneis |porcos |porsche|porta papel|porteira|portoes|pratos| prima |procura se |procuracao|procuradoria|procurase|profissao|projeto|protesto|pula pula|pula pula |punto|quadra |quadras |quadra futsal|quadriciculo|queijo|quiksilver|ranger |rapaz solteiro' THEN 1

    WHEN keyword_clean REGEXP 'rapazes|reciclaveis|refrigerado|refugio|registro de |relatorio de estagio|relogio|remo indoor|renault|rengade|responsabilidade|revenderora|rotina|roupa|roupa |roupas|s10|salario |salgados|saveiro|scania|seguro prestamista|sem consulta|sem divisoria|separacao|siena|simpatia|sindicato|sinuca|sportback|sporting|sprinter|sw4|tabela fipe |tabelionato|tabua |tambor de latao|tapeceiro|tartaruga|taxi|tecido|tecidos|telao|telefone|telescopio|telhado|telhas |tenda|terno|tiguan|tilapia|tipo de |tipos de |toalha|toldo|towner|toyata|toyota|trajes|trator|treinamento|troller|truques|tubulacao|tucson| uno |usufruto|usufrutuario|vacas |vaga corretor|vagas corretor|vagas de corretor|vagas para corretor| van |vans|vazamento |vectra|veiculo|veleiro|veloster|vendas e barganhas|vendedor|vendedora |versa|vestido|videogame|videoke|violao| vivo|volvo |voyage|vw |website|winner sport life|xj6|xre |xt |yakisoba|zoologico|aluguel de mesas|garotas de programa|garota de programa|madereira|claudio kano|seminovos |receita federal|convite para|tabela fipe|fipe tabela' THEN 1
    ELSE 0 
  END AS has_mention_to_non_related,

  CASE
    WHEN keyword_clean REGEXP '0|1|2|3|4|5|6|7|8|9' THEN 1
    ELSE 0 
  END AS has_mention_to_number,

  CASE
    WHEN keyword_clean REGEXP 'armazem|barracao|cabanas|chacara|chale|chales|cohab|coliving|comercial|conjunto comercial|container|deposito|espaco para festa|fazenda|galpao|galpoes|hoteis|hotel|loja|lote|loteamento|lotes|ponto comercial|pousada|quiosque|rancho|resort|sala comercial|sala para alugar|salao|salas|sitio|terreno|trailer|fazendinha' THEN 1
    ELSE 0 
  END AS has_mention_to_other_house_types,

  CASE
    WHEN keyword_clean REGEXP 'altitude|animais|animal|app |associacao|circuito|conta |estudante|problema|promessa|proposta|quiz|sac |de rico|preencher |luxo|chique|moderna|moderno|pequeno|rustica| linda|lembranca|lembrancinha|heranca' THEN 1
    ELSE 0 
  END AS has_mention_to_other_info,

  CASE
    WHEN keyword_clean REGEXP '123 imoveis|123i|123imoveis|4 andar|4anda|5 a|5 abdar|5 adar|5 amdar|5 anadr|5 anar|5 anda|5 andad|5 andae|5 andar|5 andart|5 andat|5 ander|5 andr|5 andra|5 andro|5 andsr|5 ansar|5 ndar|5o andar|5 qndar|5 sndar|5°andar|5° andar|5A|5amdar|5and|5anda|5andae|5andar|5andat|5andsr|5ansar|5o andar|emcasa|indica ai|loft|lopes|lugar certo|quarto andar|quimto andar|quin to|quin to mensagem|quinto|quinto amdar|quinto anda|quinto andar|quintoandar|quinti andar|quinta andar|quito andar|webimoveis|webimovel|webmoveis|webquarto|web quarto|ape11|ape 11|imovelguide|imovel guide|dream casa|lugar certo|guia facil|viva decora|tuacasa|decor facil|casa e construcao|casa abril|casa vogue|guarde mais|auxiliadora predial|moovitapp|moovit app|direcional|nestoria|vivamapio|viva mapio|secovi|trisul|arbo |qunto andar|qinto andar|auxiliardora predial|5oandar|wuinto andar|quiinto andar|5a andar|5to andar|quint andar|50 andar|quintaandar|quonto andar' THEN 1
    ELSE 0 
  END AS has_mention_to_platform,

  CASE
    WHEN keyword_clean LIKE '%sala comercial%' THEN 0
    WHEN keyword_clean LIKE 'bar %' THEN 1
    WHEN keyword_clean LIKE '% bar' THEN 1
    WHEN keyword_clean LIKE 'club %' THEN 1
    WHEN keyword_clean LIKE '% club' THEN 1
    WHEN keyword_clean REGEXP 'academia|aeroporto|agencia |arena|banca|banco 24 |banco do brasil| bar |bares|barzinho|beach |beira mar|beira rio|brt|cafe |cafes|cafeteria|caixa 24|calcadao|campeche|campus universitario|carrefour|cartorio|centro medico|centro odonto|centro olimpico|churrascaria|ciclovia|ciep|cinema|clinica|clinico| club |clube|colegio|comercial|comercio|consultorio|correios|creche|cti|disney|educacional|empresarial|empresarial |escola|esportivo|estabelecimento|estacao|estacio de sa|estadio|executivo|faculdade|farmacia|hospital|hospital |igreja|instituto|itau |linha|local |loja|lojas|medical center|mercad|metro|onibus|padaria|perto |policia|ponto |ponto comercial|pontos comerciais|posto de gasolina|praca|praia|prox|proximo |restaurante|santander |shopping|supermercado|teatro|terminal|transporte|universitaria|universitario|sesc|casa de saude|museu|parque ' THEN 1
    ELSE 0 
  END AS has_mention_to_poi,

  CASE
    WHEN keyword_clean REGEXP 'aliguel|aluga|alugo|alugue|aluguel|aluguel de|aluguel de moveis|anual|locacao|alugar|alugel' THEN 1
    ELSE 0 
  END AS has_mention_to_rent,

  CASE
    WHEN keyword_clean LIKE 'venda %' THEN 1
    WHEN keyword_clean LIKE 'vendas %' THEN 1
    WHEN keyword_clean LIKE '% venda' THEN 1
    WHEN keyword_clean LIKE 'vende %' THEN 1
    WHEN keyword_clean LIKE '% vende' THEN 1
    WHEN keyword_clean LIKE 'vender %' THEN 1
    WHEN keyword_clean LIKE '% vender' THEN 1
    WHEN keyword_clean REGEXP 'compra|compre|compro|lancamento|na planta| venda | vende |vendi |vendo | venda |para vender| vendas | vender |avenda' THEN 1
    ELSE 0 
  END AS has_mention_to_sale,

  CASE
    WHEN keyword_clean REGEXP 'aibnb|airbnb|housi|vrbo' THEN 1
    ELSE 0 
  END AS has_mention_to_short_term_homestays,

  CASE
    WHEN keyword_clean REGEXP 'apart hotel|booking|fds|final de semana|mensal' THEN 1
    ELSE 0 
  END AS has_mention_to_short_term_rental,

  CASE
    WHEN keyword_clean REGEXP 'acre |alagoas|amapa|amazonas|arizona|bahia|california|ceara|espirito santo|florida|goias|maranhao|mato grosso|mato grosso do sul|minas gerais|paraiba|parana|pernambuco|rio de janeiro|rio grande do norte|rio grande do sul|rondonia|roraima|santa catarina|sao paulo|sergipe|texas|tocantins| mg| df| rs| rr| rn| sc| rj| sp' THEN 1
    ELSE 0 
  END AS has_mention_to_state,

  CASE
    WHEN CONTAINS(keyword_clean, 'ipca 20') THEN 0
    WHEN keyword_clean REGEXP 'segunda via ' THEN 0
    WHEN keyword_clean LIKE 'r %' THEN 1
    WHEN keyword_clean LIKE 'r. %' THEN 1
    WHEN keyword_clean LIKE 'al %' THEN 1
    WHEN keyword_clean LIKE 'av %' THEN 1
    WHEN keyword_clean LIKE 'av. %' THEN 1
    WHEN keyword_clean REGEXP 'alameda|asa leste|asa norte|asa oeste|asa sul|avenida|baia |beco |estr |estrada|ladeira |largo |praca |qr |quadra |rodovia |rua |servidao |sqn |travessa|via |viela ' THEN 1
    ELSE 0
  END AS has_mention_to_street,

  CASE
    WHEN keyword_clean LIKE '%chaves na mao%' THEN 0
    WHEN keyword_clean LIKE '%chave na mao%' THEN 0 
    WHEN keyword_clean LIKE '%direto com o proprietario%' THEN 0
    WHEN keyword_clean LIKE '%direto proprietario%' THEN 0
    WHEN keyword_clean LIKE 'o proprietario %' THEN 1
    WHEN keyword_clean REGEXP 'a partir de que|aditivo|administracao|aliquota|aluguel atrasado|antecipacao|anulacao|anuncio|aplicativo|ate quantos|atualizacao|atualizar|aumento|aumento de aluguel|aviso|boleto|burocracia|calculadora|calcular|calcule o valor|calculo|cancelar|cartorio|casa verde e amarela|caucao|certidao|chaves|clausula|cobranca|cobrar|codigo|com parcelas|como alugar|como preencher|comprovante|comprovar|consulta|contrato|correcao|credito|declaracao|declarar|deposito|desistencia|desocupacao|despejo|despesa|direito|direitos |distrato|dividir aluguel|documento|documentos|emprestimo|entrada para financiamento|entrega das chaves|escritura|facilitado|fatura|fiador|fiananciamento|fianca|financiado|financiamento|financiar|formulario|fundo de reserva|garantia|horario de mudanca|inquilinato|inquilino|locador|localizar|locatario|manual |matricula|mcmv|minha casa minha vida|minha casas minha vida|modelo |modelo de recibo de locacao|moradia|morando|multa|multa por nao declarar aluguel pago|negociar|notificacao|o fiador pode| o proprietario|o proprietario pode|pagamento|pagar |patrocinio online casas para alugar|postecipado|prazo|programa verde e amarelo|quebra de contrato|recebimento|recibo|recibo de aluguel para preencher online|recisao|registro|regras |rendimento|rentabilidade|rescisao|seguro fianca|sem burocracia|simulador|simular|solicitacao|sublocacao|termo|termo de entrega|titulo|titulo de capitalizacao|trasnferencia de |usucapiao|valor de aluguel|vencimento|verde amarela|verde e amarela|verde e amarelo|vistoria' THEN 1
    ELSE 0 
  END AS has_mention_to_transaction_info_doubts,

  CASE
    WHEN keyword_clean REGEXP 'alugue temporada|ano novo|carnaval|feriado|final de ano|pascoa|reveillon|semana santa|temporada|village|viagem|ferias|viajar|final de semana' THEN 1
    ELSE 0 
  END AS has_mention_to_vacation,

  CASE
    WHEN CONTAINS(keyword_clean, 'casas para alugar em ') THEN 'casas para alugar em'
    WHEN CONTAINS(keyword_clean, 'casas para alugar') THEN 'casas para alugar'
    WHEN CONTAINS(keyword_clean, 'apartamento para alugar') THEN 'apartamento para alugar'
    WHEN CONTAINS(keyword_clean, 'apartamento alugar em ') THEN 'apartamento alugar em'
    WHEN CONTAINS(keyword_clean, 'apartamento alugar') THEN 'apartamento alugar'
    WHEN CONTAINS(keyword_clean, 'casa para alugar em ') THEN 'casa para alugar em'
    WHEN CONTAINS(keyword_clean, 'casa para alugar') THEN 'casa para alugar'
    WHEN CONTAINS(keyword_clean, 'aluguel apartamento') THEN 'aluguel apartamento'
    WHEN CONTAINS(keyword_clean, 'casas alugar') THEN 'casas alugar'
    WHEN CONTAINS(keyword_clean, 'casas de aluguel') THEN 'casas de aluguel'
    WHEN CONTAINS(keyword_clean, 'casa alugar') THEN 'casa alugar'
    WHEN CONTAINS(keyword_clean, 'alugar casa em ') THEN 'alugar casa em'
    WHEN CONTAINS(keyword_clean, 'alugar casa') THEN 'alugar casa'
    WHEN CONTAINS(keyword_clean, 'aluguel casa') THEN 'aluguel casa'
    WHEN CONTAINS(keyword_clean, 'aluguel temporada') THEN 'aluguel temporada'
    WHEN CONTAINS(keyword_clean, 'aluguel anual') THEN 'aluguel anual'
    WHEN CONTAINS(keyword_clean, 'casa aluguel') THEN 'casa aluguel'
    WHEN CONTAINS(keyword_clean, 'casas para aluguel') THEN 'casas para aluguel'
    WHEN CONTAINS(keyword_clean, 'kitnet') THEN 'kitnet'
    WHEN CONTAINS(keyword_clean, 'sitio') THEN 'sitio'
    WHEN CONTAINS(keyword_clean, 'chacara') THEN 'chacara'
    WHEN CONTAINS(keyword_clean, 'apartamento') THEN 'apartamento'
    WHEN CONTAINS(keyword_clean, 'imoveis') THEN 'imoveis'
    WHEN CONTAINS(keyword_clean, 'casa') THEN 'casa'
    WHEN CONTAINS(keyword_clean, 'condominio') THEN 'condominio'
    WHEN CONTAINS(keyword_clean, 'alugar em ') THEN 'alugar em'
    WHEN CONTAINS(keyword_clean, 'alugar') THEN 'alugar'
    WHEN CONTAINS(keyword_clean, 'aluguel em ') THEN 'aluguel em'
    WHEN CONTAINS(keyword_clean, 'aluguel de ') THEN 'aluguel de'
    WHEN CONTAINS(keyword_clean, 'aluguel') THEN 'aluguel'
    WHEN CONTAINS(keyword_clean, 'alugue') THEN 'alugue'
    ELSE ''
  END AS rent_subcategories,
  year,
  month,
  day 
FROM
  datalake_google_search_console.gsc_keyword_region_attributes
WHERE
  dt_created BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
