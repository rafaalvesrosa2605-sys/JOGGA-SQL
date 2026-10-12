-- =============================================================================
-- JOGGA - Sistema de agendamento de quadras (PIM II - UNIP)
-- Script 01: criacao do banco de dados e das tabelas (modelo fisico)
--
-- SGBD..........: MySQL 8 (testado no 8.4 LTS), motor InnoDB, charset utf8mb4
-- Organizacao...: Arena Meio-Campo Esportes (ficticia) - 5 quadras
-- Ordem.........: 01_criacao -> 02_dados_exemplo -> 03_views_triggers_procedures
--                 -> 04_consultas -> 05_testes
--
-- ATENCAO: este script APAGA e recria o banco "jogga". Serve para deixar o
-- ambiente sempre igual antes de rodar os demais scripts (inclusive os testes).
--
-- Convencoes adotadas (iguais ao codigo em C):
--   * nomes em portugues, snake_case, sem acento;
--   * chave primaria "id_<tabela>" e chave estrangeira com o mesmo nome da PK
--     referenciada (ex.: reserva.id_quadra -> quadra.id_quadra);
--   * dia_semana segue a funcao DAYOFWEEK() do MySQL: 1 = domingo ... 7 = sabado
--     (no PostgreSQL o equivalente e EXTRACT(DOW FROM data) + 1);
--   * horario de funcionamento 08h-23h, reservas de 1 hora, ultimo inicio 22h
--     (mesmas constantes HORA_ABERTURA/HORA_FECHAMENTO de src/modelo/agendamento.h).
--
-- Notas de portabilidade para PostgreSQL estao marcadas com [PG].
-- =============================================================================

-- Garante que o cliente envie os comandos em UTF-8, qualquer que seja o
-- charset do terminal (no Windows o console usa cp850 por padrao).
SET NAMES utf8mb4;

DROP DATABASE IF EXISTS jogga;

-- utf8mb4 armazena qualquer caractere Unicode (acentos, cedilha e ate emoji nos
-- comentarios de avaliacao). A collation _ai_ci ignora acento e caixa nas
-- comparacoes: buscar "joao" encontra "Joao" e "JOAO".
CREATE DATABASE jogga
    CHARACTER SET utf8mb4
    COLLATE utf8mb4_0900_ai_ci;

USE jogga;

-- -----------------------------------------------------------------------------
-- 1. USUARIO
-- Qualquer pessoa que acessa o sistema. O perfil define o que ela pode fazer:
--   CLIENTE  - jogador que reserva quadras (no codigo C: PERFIL_CLIENTE)
--   RECEPCAO - funcionario do balcao; reserva em nome de clientes, registra
--              pagamentos em dinheiro e marca no-show
--   ADMIN    - gestor; cadastra quadras e precos e ve os relatorios
--              (no codigo C: PERFIL_ADMIN)
-- Por que guardar senha_hash e nao a senha: se o banco vazar, o atacante nao
-- descobre as senhas (o hash bcrypt nao pode ser revertido). Isso corrige a
-- limitacao do prototipo em C (senha em texto puro nos arquivos .dat).
-- aceite_lgpd registra QUANDO o titular consentiu com o tratamento dos dados
-- (LGPD, art. 8o: o controlador deve conseguir provar o consentimento).
-- -----------------------------------------------------------------------------
CREATE TABLE usuario (
    id_usuario   INT UNSIGNED  NOT NULL AUTO_INCREMENT,
    nome         VARCHAR(100)  NOT NULL,
    cpf          CHAR(11)      NOT NULL,          -- so digitos, sem pontuacao
    email        VARCHAR(120)  NOT NULL,          -- tambem e o login
    telefone     VARCHAR(15)   NOT NULL,          -- ex.: 11987654321
    senha_hash   VARCHAR(255)  NOT NULL,          -- bcrypt ($2b$...) - nunca a senha
    perfil       ENUM('CLIENTE','RECEPCAO','ADMIN') NOT NULL DEFAULT 'CLIENTE',
    aceite_lgpd  DATETIME      NULL,              -- NULL = ainda nao aceitou
    criado_em    DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT pk_usuario       PRIMARY KEY (id_usuario),
    -- Os dois UNIQUE abaixo ja criam indices B-tree. Por isso NAO criamos um
    -- indice separado em email: uk_usuario_email e o indice usado no login
    -- (WHERE email = ?). Um segundo indice na mesma coluna so gastaria espaco.
    CONSTRAINT uk_usuario_cpf   UNIQUE (cpf),
    CONSTRAINT uk_usuario_email UNIQUE (email),
    CONSTRAINT ck_usuario_cpf   CHECK (cpf REGEXP '^[0-9]{11}$'),
    CONSTRAINT ck_usuario_email CHECK (email LIKE '%_@_%._%')
) ENGINE = InnoDB
  COMMENT = 'Clientes, recepcionistas e administradores do JOGGA';
-- [PG] ENUM: usar VARCHAR(10) + CHECK (perfil IN (...)) ou CREATE TYPE.
-- [PG] AUTO_INCREMENT: usar INT GENERATED ALWAYS AS IDENTITY. REGEXP: usar ~.


-- -----------------------------------------------------------------------------
-- 2. MODALIDADE
-- Esportes oferecidos (futebol society, futsal, volei...). Fica em tabela
-- propria, e nao como texto dentro de quadra, porque uma quadra atende varias
-- modalidades e uma modalidade existe em varias quadras (relacao N:N). Assim
-- o nome e escrito uma unica vez (3FN) e relatorios por esporte ficam simples.
-- -----------------------------------------------------------------------------
CREATE TABLE modalidade (
    id_modalidade SMALLINT UNSIGNED NOT NULL AUTO_INCREMENT,
    nome          VARCHAR(40)       NOT NULL,

    CONSTRAINT pk_modalidade      PRIMARY KEY (id_modalidade),
    CONSTRAINT uk_modalidade_nome UNIQUE (nome)
) ENGINE = InnoDB
  COMMENT = 'Esportes praticados na arena';


-- -----------------------------------------------------------------------------
-- 3. QUADRA
-- Cada espaco fisico alugavel. Em vez de apagar uma quadra que saiu de uso,
-- marcamos ativa = FALSE: o historico de reservas dela continua valido para
-- os relatorios (e o banco nem deixa apagar quadra com reservas - ver FKs).
-- O preco NAO fica aqui (diferente da struct Quadra em C, que tem valor_hora):
-- como o preco varia por dia e horario (horario de pico), ele foi para
-- tabela_preco. Manter um valor fixo aqui criaria duas fontes de verdade.
-- -----------------------------------------------------------------------------
CREATE TABLE quadra (
    id_quadra   SMALLINT UNSIGNED NOT NULL AUTO_INCREMENT,
    nome        VARCHAR(40)       NOT NULL,
    tipo_piso   VARCHAR(30)       NOT NULL,       -- grama sintetica, madeira, areia...
    coberta     BOOLEAN           NOT NULL DEFAULT FALSE,
    capacidade  TINYINT UNSIGNED  NOT NULL,       -- jogadores em quadra ao mesmo tempo
    ativa       BOOLEAN           NOT NULL DEFAULT TRUE,

    CONSTRAINT pk_quadra            PRIMARY KEY (id_quadra),
    CONSTRAINT uk_quadra_nome       UNIQUE (nome),
    CONSTRAINT ck_quadra_capacidade CHECK (capacidade > 0)
) ENGINE = InnoDB
  COMMENT = 'Quadras do complexo esportivo';
-- [PG] BOOLEAN existe nativamente; no MySQL BOOLEAN e um apelido de TINYINT(1).


-- -----------------------------------------------------------------------------
-- 4. QUADRA_MODALIDADE (tabela associativa N:N)
-- Diz quais esportes cada quadra comporta: a poliesportiva recebe volei e
-- basquete; a de areia recebe beach tennis e futevolei.
-- PK composta (id_quadra, id_modalidade): o proprio par e o identificador e
-- impede cadastrar a mesma modalidade duas vezes na mesma quadra.
-- ON DELETE CASCADE aqui faz sentido: a linha so descreve uma caracteristica
-- da quadra; sem a quadra (ou sem a modalidade) ela nao significa nada.
-- Isso nao abre brecha: se a quadra tiver reservas, a FK de reserva (que
-- aponta para esta tabela com RESTRICT) bloqueia a exclusao em cascata.
-- -----------------------------------------------------------------------------
CREATE TABLE quadra_modalidade (
    id_quadra     SMALLINT UNSIGNED NOT NULL,
    id_modalidade SMALLINT UNSIGNED NOT NULL,

    CONSTRAINT pk_quadra_modalidade PRIMARY KEY (id_quadra, id_modalidade),
    CONSTRAINT fk_qm_quadra     FOREIGN KEY (id_quadra)
        REFERENCES quadra (id_quadra)         ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT fk_qm_modalidade FOREIGN KEY (id_modalidade)
        REFERENCES modalidade (id_modalidade) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE = InnoDB
  COMMENT = 'Modalidades que cada quadra comporta (N:N)';


-- -----------------------------------------------------------------------------
-- 5. HORARIO_FUNCIONAMENTO
-- Abertura e fechamento de cada quadra em cada dia da semana. O padrao e
-- 08h-23h, mas a tabela permite excecoes sem mexer no codigo (ex.: a quadra
-- de areia fecha as 22h por nao ter iluminacao suficiente).
-- PK (id_quadra, dia_semana): cada quadra tem no maximo uma faixa por dia.
-- CASCADE: e configuracao da quadra, nao tem valor historico proprio.
-- -----------------------------------------------------------------------------
CREATE TABLE horario_funcionamento (
    id_quadra       SMALLINT UNSIGNED NOT NULL,
    dia_semana      TINYINT UNSIGNED  NOT NULL,   -- 1 = domingo ... 7 = sabado
    hora_abertura   TIME              NOT NULL,
    hora_fechamento TIME              NOT NULL,

    CONSTRAINT pk_horario_funcionamento PRIMARY KEY (id_quadra, dia_semana),
    CONSTRAINT fk_hf_quadra FOREIGN KEY (id_quadra)
        REFERENCES quadra (id_quadra) ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT ck_hf_dia_semana CHECK (dia_semana BETWEEN 1 AND 7),
    CONSTRAINT ck_hf_faixa      CHECK (hora_fechamento > hora_abertura),
    -- a arena inteira funciona dentro de 08h-23h; nenhuma quadra pode fugir disso
    CONSTRAINT ck_hf_limites    CHECK (hora_abertura >= '08:00:00'
                                   AND hora_fechamento <= '23:00:00')
) ENGINE = InnoDB
  COMMENT = 'Horario de abertura/fechamento por quadra e dia da semana';


-- -----------------------------------------------------------------------------
-- 6. TABELA_PRECO (preco dinamico)
-- Valor da hora por quadra, dia da semana e faixa de horario. Ex.: society em
-- dia util custa R$ 150 ate 17h e R$ 220 no pico (17h-23h).
-- A faixa e semiaberta [hora_inicio, hora_fim): uma reserva das 17h cai na
-- faixa 17h-23h, nao na 08h-17h.
-- O UNIQUE impede duas faixas comecando no mesmo horario. Sobreposicao parcial
-- de faixas (08-18 e 17-23) nao da para impedir so com CHECK/UNIQUE no MySQL;
-- isso fica a cargo da tela de cadastro de precos. [PG] la seria possivel com
-- uma EXCLUDE constraint sobre tsrange.
-- id_preco proprio (surrogate) porque a chave natural tem 3 colunas e seria
-- incomoda para editar/apagar faixas pela tela do administrador.
-- -----------------------------------------------------------------------------
CREATE TABLE tabela_preco (
    id_preco    INT UNSIGNED      NOT NULL AUTO_INCREMENT,
    id_quadra   SMALLINT UNSIGNED NOT NULL,
    dia_semana  TINYINT UNSIGNED  NOT NULL,
    hora_inicio TIME              NOT NULL,
    hora_fim    TIME              NOT NULL,
    valor_hora  DECIMAL(8,2)      NOT NULL,       -- DECIMAL: dinheiro nunca em FLOAT

    CONSTRAINT pk_tabela_preco PRIMARY KEY (id_preco),
    CONSTRAINT uk_tabela_preco_faixa UNIQUE (id_quadra, dia_semana, hora_inicio),
    CONSTRAINT fk_tp_quadra FOREIGN KEY (id_quadra)
        REFERENCES quadra (id_quadra) ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT ck_tp_dia_semana CHECK (dia_semana BETWEEN 1 AND 7),
    CONSTRAINT ck_tp_faixa      CHECK (hora_fim > hora_inicio),
    CONSTRAINT ck_tp_limites    CHECK (hora_inicio >= '08:00:00' AND hora_fim <= '23:00:00'),
    CONSTRAINT ck_tp_valor      CHECK (valor_hora > 0)
) ENGINE = InnoDB
  COMMENT = 'Preco por hora conforme quadra, dia e faixa de horario';
-- Por que DECIMAL e nao FLOAT (a struct em C usa float): FLOAT e binario e nao
-- representa 0,10 exatamente; somar centavos em FLOAT gera diferencas de
-- arredondamento em relatorios financeiros.


-- -----------------------------------------------------------------------------
-- 7. RESERVA (tabela central)
-- Uma reserva = uma quadra, um dia, uma hora (equivale a struct Agendamento).
-- Ciclo de vida do status:
--   PENDENTE   -> criada, aguardando o sinal (Pix)
--   CONFIRMADA -> sinal pago, horario garantido
--   CONCLUIDA  -> jogo aconteceu
--   NO_SHOW    -> cliente nao apareceu nem cancelou (indicador para o gestor)
--   CANCELADA  -> cancelada; o horario VOLTA a ficar livre
-- valor_total e copiado da tabela_preco no momento da reserva (nao calculado
-- depois) porque o preco pode mudar: a reserva guarda o preco combinado.
-- Nao apagamos reservas canceladas (status em vez de DELETE): o historico
-- alimenta relatorios de cancelamento e a auditoria.
--
-- >>> REGRA PRINCIPAL (RN01): nunca duas reservas na mesma quadra/dia/hora <<<
-- Um UNIQUE (id_quadra, data_reserva, hora_inicio) simples NAO serve, porque
-- uma reserva CANCELADA continuaria ocupando o horario e ninguem mais poderia
-- reserva-lo. O MySQL nao tem indice parcial (UNIQUE ... WHERE status <> ...),
-- entao usamos uma COLUNA GERADA:
--
--   hora_bloqueada = NULL         se status = 'CANCELADA'
--                  = hora_inicio  nos demais status
--
-- e o UNIQUE e feito sobre (id_quadra, data_reserva, hora_bloqueada).
-- Em indices UNIQUE, NULL nunca e igual a NULL (padrao SQL), entao quantas
-- reservas canceladas existirem no mesmo horario nao conflitam entre si nem
-- com a reserva ativa. Ja duas reservas ativas no mesmo horario geram o erro
-- 1062 (Duplicate entry) - e o BANCO quem garante, mesmo que dois clientes
-- cliquem em "reservar" no mesmo milissegundo ou que alguem esqueca a
-- validacao no codigo (no C a mesma regra e validar_conflito()).
-- STORED (gravada em disco) porque o InnoDB indexa a coluna gerada e o valor
-- e recalculado automaticamente a cada UPDATE de status.
-- [PG] Nao precisa de coluna gerada:
--   CREATE UNIQUE INDEX uk_reserva_horario ON reserva (id_quadra, data_reserva, hora_inicio)
--       WHERE status <> 'CANCELADA';
-- -----------------------------------------------------------------------------
CREATE TABLE reserva (
    id_reserva     INT UNSIGNED      NOT NULL AUTO_INCREMENT,
    id_usuario     INT UNSIGNED      NOT NULL,    -- quem reservou (dono da reserva)
    id_quadra      SMALLINT UNSIGNED NOT NULL,
    id_modalidade  SMALLINT UNSIGNED NOT NULL,
    data_reserva   DATE              NOT NULL,
    hora_inicio    TIME              NOT NULL,
    hora_fim       TIME              NOT NULL,
    status         ENUM('PENDENTE','CONFIRMADA','CANCELADA','CONCLUIDA','NO_SHOW')
                                     NOT NULL DEFAULT 'PENDENTE',
    valor_total    DECIMAL(8,2)      NOT NULL,
    criado_em      DATETIME          NOT NULL DEFAULT CURRENT_TIMESTAMP,
    atualizado_em  DATETIME          NOT NULL DEFAULT CURRENT_TIMESTAMP
                                     ON UPDATE CURRENT_TIMESTAMP,
    -- coluna gerada que implementa a regra principal (ver explicacao acima)
    hora_bloqueada TIME GENERATED ALWAYS AS
                   (CASE WHEN status = 'CANCELADA' THEN NULL ELSE hora_inicio END) STORED,

    CONSTRAINT pk_reserva PRIMARY KEY (id_reserva),
    CONSTRAINT uk_reserva_horario UNIQUE (id_quadra, data_reserva, hora_bloqueada),

    CONSTRAINT fk_reserva_usuario FOREIGN KEY (id_usuario)
        REFERENCES usuario (id_usuario) ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_reserva_quadra FOREIGN KEY (id_quadra)
        REFERENCES quadra (id_quadra)   ON DELETE RESTRICT ON UPDATE CASCADE,
    -- FK composta para quadra_modalidade: alem de a modalidade existir, ela
    -- precisa ser OFERECIDA naquela quadra (nao da para reservar "beach
    -- tennis" na quadra de futsal). Uma FK simples para modalidade nao
    -- garantiria isso.
    CONSTRAINT fk_reserva_quadra_modalidade FOREIGN KEY (id_quadra, id_modalidade)
        REFERENCES quadra_modalidade (id_quadra, id_modalidade)
        ON DELETE RESTRICT ON UPDATE CASCADE,

    CONSTRAINT ck_reserva_ordem      CHECK (hora_fim > hora_inicio),
    -- RN02: inicio entre 08h e 22h (a ultima reserva termina as 23h)
    CONSTRAINT ck_reserva_inicio     CHECK (hora_inicio BETWEEN '08:00:00' AND '22:00:00'),
    -- reservas comecam em hora cheia (19:00, nunca 19:30), como no codigo C
    CONSTRAINT ck_reserva_hora_cheia CHECK (MINUTE(hora_inicio) = 0 AND SECOND(hora_inicio) = 0),
    -- cada reserva dura exatamente 1 hora
    CONSTRAINT ck_reserva_duracao    CHECK (hora_fim = ADDTIME(hora_inicio, '01:00:00')),
    CONSTRAINT ck_reserva_valor      CHECK (valor_total > 0)
) ENGINE = InnoDB
  COMMENT = 'Reservas de quadra (1 hora cada) - tabela central do sistema';

-- Indices pedidos para as consultas mais frequentes:
--   agenda do dia / horarios livres filtram por data;
--   "minhas reservas" filtra por usuario.
-- (Sem idx_reserva_usuario o InnoDB criaria sozinho um indice para a FK; ao
--  criar com nome explicito o DER/dicionario de dados fica mais claro.)
CREATE INDEX idx_reserva_data    ON reserva (data_reserva);
CREATE INDEX idx_reserva_usuario ON reserva (id_usuario);
-- Nota: data_reserva com DATE e nao VARCHAR(10) como no C ("AAAA-MM-DD"):
-- o SGBD valida a data (2026-02-30 e recusada) e permite calculos de datas.
-- Datas no passado sao barradas em sp_reservar (CHECK nao aceita CURDATE(),
-- pois o resultado mudaria com o tempo).


-- -----------------------------------------------------------------------------
-- 8. PARTICIPANTE_RESERVA ("racha dividido")
-- Quem vai jogar e quanto cada um paga. O dono da reserva convida os amigos e
-- cada um paga a sua cota; assim a recepcao sabe quanto falta receber.
-- PK (id_reserva, id_usuario): a mesma pessoa nao entra duas vezes no racha.
-- CASCADE da reserva: as cotas so existem dentro da reserva. (Na pratica
-- reservas quase nunca sao apagadas - sao canceladas - e se tiverem
-- pagamento a FK de pagamento impede o DELETE.)
-- RESTRICT do usuario: nao some com a cota de alguem que ainda deve.
-- -----------------------------------------------------------------------------
CREATE TABLE participante_reserva (
    id_reserva       INT UNSIGNED NOT NULL,
    id_usuario       INT UNSIGNED NOT NULL,
    valor_cota       DECIMAL(8,2) NOT NULL,
    status_pagamento ENUM('PENDENTE','PAGO') NOT NULL DEFAULT 'PENDENTE',
    pago_em          DATETIME     NULL,

    CONSTRAINT pk_participante_reserva PRIMARY KEY (id_reserva, id_usuario),
    CONSTRAINT fk_pr_reserva FOREIGN KEY (id_reserva)
        REFERENCES reserva (id_reserva) ON DELETE CASCADE  ON UPDATE CASCADE,
    CONSTRAINT fk_pr_usuario FOREIGN KEY (id_usuario)
        REFERENCES usuario (id_usuario) ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT ck_pr_valor CHECK (valor_cota > 0),
    -- coerencia: cota PAGA precisa da data; cota PENDENTE nao pode ter data
    CONSTRAINT ck_pr_pago  CHECK ((status_pagamento = 'PAGO') = (pago_em IS NOT NULL))
) ENGINE = InnoDB
  COMMENT = 'Divisao do valor da reserva entre os jogadores (racha)';


-- -----------------------------------------------------------------------------
-- 9. PAGAMENTO
-- Cada entrada de dinheiro (ou tentativa) ligada a uma reserva. Uma reserva
-- pode ter varios pagamentos: sinal de 50% por Pix + restante no balcao.
-- RESTRICT (e nao CASCADE): registro financeiro nao pode desaparecer junto
-- com a reserva; a contabilidade precisa do historico, inclusive estornos.
-- -----------------------------------------------------------------------------
CREATE TABLE pagamento (
    id_pagamento INT UNSIGNED NOT NULL AUTO_INCREMENT,
    id_reserva   INT UNSIGNED NOT NULL,
    forma        ENUM('PIX','CARTAO','DINHEIRO') NOT NULL,
    valor        DECIMAL(8,2) NOT NULL,
    status       ENUM('PENDENTE','APROVADO','RECUSADO','ESTORNADO') NOT NULL DEFAULT 'PENDENTE',
    pago_em      DATETIME     NULL,               -- preenchido quando aprovado
    criado_em    DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT pk_pagamento PRIMARY KEY (id_pagamento),
    CONSTRAINT fk_pagamento_reserva FOREIGN KEY (id_reserva)
        REFERENCES reserva (id_reserva) ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT ck_pagamento_valor CHECK (valor > 0),
    -- aprovado ou estornado implica que o dinheiro chegou a entrar
    CONSTRAINT ck_pagamento_data  CHECK (status IN ('PENDENTE','RECUSADO') OR pago_em IS NOT NULL)
) ENGINE = InnoDB
  COMMENT = 'Pagamentos (sinal, restante, estornos) das reservas';


-- -----------------------------------------------------------------------------
-- 10. LISTA_ESPERA
-- Interessados em um horario que ja esta ocupado. Quando a reserva daquele
-- horario e cancelada, o trigger trg_reserva_au marca o 1o da fila como
-- NOTIFICADO (o app manda o push/WhatsApp). Colunas status e notificado_em
-- foram acrescentadas ao modelo pedido justamente para registrar isso.
-- posicao e preenchida automaticamente pelo trigger trg_lista_espera_bi.
-- CASCADE no usuario: se o titular pedir exclusao dos dados (LGPD), a
-- inscricao na fila deixa de fazer sentido. RESTRICT na quadra.
-- -----------------------------------------------------------------------------
CREATE TABLE lista_espera (
    id_espera     INT UNSIGNED      NOT NULL AUTO_INCREMENT,
    id_usuario    INT UNSIGNED      NOT NULL,
    id_quadra     SMALLINT UNSIGNED NOT NULL,
    data_reserva  DATE              NOT NULL,
    hora_inicio   TIME              NOT NULL,
    posicao       SMALLINT UNSIGNED NOT NULL,
    status        ENUM('AGUARDANDO','NOTIFICADO','ATENDIDO','DESISTIU')
                                    NOT NULL DEFAULT 'AGUARDANDO',
    notificado_em DATETIME          NULL,
    criado_em     DATETIME          NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT pk_lista_espera PRIMARY KEY (id_espera),
    -- a mesma pessoa nao entra duas vezes na fila do mesmo horario
    CONSTRAINT uk_le_usuario_horario UNIQUE (id_usuario, id_quadra, data_reserva, hora_inicio),
    -- duas pessoas nao ocupam a mesma posicao da mesma fila
    CONSTRAINT uk_le_posicao         UNIQUE (id_quadra, data_reserva, hora_inicio, posicao),
    CONSTRAINT fk_le_usuario FOREIGN KEY (id_usuario)
        REFERENCES usuario (id_usuario) ON DELETE CASCADE  ON UPDATE CASCADE,
    CONSTRAINT fk_le_quadra  FOREIGN KEY (id_quadra)
        REFERENCES quadra (id_quadra)   ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT ck_le_inicio  CHECK (hora_inicio BETWEEN '08:00:00' AND '22:00:00'),
    CONSTRAINT ck_le_posicao CHECK (posicao > 0)
) ENGINE = InnoDB
  COMMENT = 'Fila de espera por horarios ocupados';


-- -----------------------------------------------------------------------------
-- 11. MENSALISTA
-- Cliente fixo: toda semana, no mesmo dia e horario (ex.: toda terca 19h na
-- Society 1). E o principal processo manual citado pela recepcao.
-- Mesma tecnica da reserva: hora_bloqueada so tem valor enquanto ativo = TRUE,
-- e o UNIQUE impede dois mensalistas ATIVOS no mesmo horario semanal da mesma
-- quadra, mas permite manter o historico dos que ja sairam.
-- sp_reservar tambem consulta esta tabela para nao vender a terceiros o
-- horario de um mensalista.
-- -----------------------------------------------------------------------------
CREATE TABLE mensalista (
    id_mensalista  INT UNSIGNED      NOT NULL AUTO_INCREMENT,
    id_usuario     INT UNSIGNED      NOT NULL,
    id_quadra      SMALLINT UNSIGNED NOT NULL,
    dia_semana     TINYINT UNSIGNED  NOT NULL,
    hora_inicio    TIME              NOT NULL,
    data_inicio    DATE              NOT NULL,
    data_fim       DATE              NULL,        -- NULL = sem data para terminar
    ativo          BOOLEAN           NOT NULL DEFAULT TRUE,
    hora_bloqueada TIME GENERATED ALWAYS AS
                   (CASE WHEN ativo THEN hora_inicio ELSE NULL END) STORED,

    CONSTRAINT pk_mensalista PRIMARY KEY (id_mensalista),
    CONSTRAINT uk_mensalista_horario UNIQUE (id_quadra, dia_semana, hora_bloqueada),
    CONSTRAINT fk_mensalista_usuario FOREIGN KEY (id_usuario)
        REFERENCES usuario (id_usuario) ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_mensalista_quadra  FOREIGN KEY (id_quadra)
        REFERENCES quadra (id_quadra)   ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT ck_mensalista_dia     CHECK (dia_semana BETWEEN 1 AND 7),
    CONSTRAINT ck_mensalista_inicio  CHECK (hora_inicio BETWEEN '08:00:00' AND '22:00:00'
                                        AND MINUTE(hora_inicio) = 0),
    CONSTRAINT ck_mensalista_periodo CHECK (data_fim IS NULL OR data_fim > data_inicio)
) ENGINE = InnoDB
  COMMENT = 'Clientes com horario fixo semanal';
-- [PG] CREATE UNIQUE INDEX ... ON mensalista (id_quadra, dia_semana, hora_inicio) WHERE ativo;


-- -----------------------------------------------------------------------------
-- 12. AVALIACAO
-- Nota de 1 a 5 dada pelo cliente depois do jogo. UNIQUE em id_reserva: uma
-- avaliacao por reserva (relacao 1:1 opcional). Por ser ligada a reserva, e
-- nao direto a quadra, so avalia quem realmente jogou; a quadra avaliada e
-- obtida pelo JOIN com reserva (evita dependencia transitiva - 3FN).
-- Que a reserva esteja CONCLUIDA e garantido pelo trigger trg_avaliacao_bi.
-- CASCADE: a avaliacao nao tem sentido sem a reserva.
-- -----------------------------------------------------------------------------
CREATE TABLE avaliacao (
    id_avaliacao INT UNSIGNED     NOT NULL AUTO_INCREMENT,
    id_reserva   INT UNSIGNED     NOT NULL,
    nota         TINYINT UNSIGNED NOT NULL,
    comentario   VARCHAR(500)     NULL,
    criado_em    DATETIME         NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT pk_avaliacao         PRIMARY KEY (id_avaliacao),
    CONSTRAINT uk_avaliacao_reserva UNIQUE (id_reserva),
    CONSTRAINT fk_avaliacao_reserva FOREIGN KEY (id_reserva)
        REFERENCES reserva (id_reserva) ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT ck_avaliacao_nota    CHECK (nota BETWEEN 1 AND 5)
) ENGINE = InnoDB
  COMMENT = 'Avaliacao (1 a 5) feita apos o jogo';


-- -----------------------------------------------------------------------------
-- 13. LOG_AUDITORIA
-- Trilha de auditoria: quem mudou o que e quando (pilar de integridade e
-- rastreabilidade citado na secao de seguranca/LGPD do PIM). Preenchida pelos
-- triggers do script 03.
-- Propositalmente SEM chave estrangeira: o log precisa sobreviver mesmo se o
-- registro original ou o usuario forem apagados/anonimizados, e uma FK
-- impediria isso (RESTRICT) ou apagaria o log (CASCADE).
-- id_usuario vem da variavel de sessao @id_usuario_app, que a aplicacao define
-- apos o login (SET @id_usuario_app = 7;). NULL = alteracao feita direto no
-- banco/sistema.
-- detalhes em JSON: cada acao tem campos diferentes (status antigo/novo,
-- quem foi notificado...), e JSON evita criar uma coluna para cada caso.
-- -----------------------------------------------------------------------------
CREATE TABLE log_auditoria (
    id_log      BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    tabela      VARCHAR(40)     NOT NULL,
    id_registro INT UNSIGNED    NOT NULL,
    acao        VARCHAR(30)     NOT NULL,         -- INSERT, STATUS, DELETE, NOTIFICAR_ESPERA
    id_usuario  INT UNSIGNED    NULL,
    data_hora   DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    detalhes    JSON            NULL,

    CONSTRAINT pk_log_auditoria PRIMARY KEY (id_log)
) ENGINE = InnoDB
  COMMENT = 'Trilha de auditoria gravada pelos triggers';
-- consulta tipica: "historico da reserva 32" -> WHERE tabela = ? AND id_registro = ?
CREATE INDEX idx_log_registro ON log_auditoria (tabela, id_registro);
-- [PG] JSON -> JSONB; JSON_OBJECT() -> json_build_object().
