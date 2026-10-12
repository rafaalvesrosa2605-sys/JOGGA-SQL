-- =============================================================================
-- JOGGA - Script 02: dados de exemplo
-- Pre-requisito: 01_criacao.sql
--
-- Decisoes importantes:
--   * As datas sao RELATIVAS ao dia em que o script roda (CURDATE() +/- N dias).
--     Assim sempre existem reservas passadas (concluidas, no-show), reservas
--     de HOJE (para a agenda do dia) e reservas futuras, nao importa quando o
--     professor executar o script.
--   * O valor de cada reserva nao e digitado: e buscado na tabela_preco
--     conforme a quadra, o dia da semana e a hora - a mesma regra que a
--     procedure sp_reservar usa.
--   * Senhas: apenas hashes bcrypt FICTICIOS (formato $2b$12$...). Nenhuma
--     senha em texto puro e gravada. CPFs ficticios, com digito verificador
--     valido. E-mails no dominio reservado exemplo.com.br.
--   * Os ids sao informados explicitamente para que 04_consultas e 05_testes
--     possam citar "reserva 32", "usuario 11" etc.
-- =============================================================================

USE jogga;

-- -----------------------------------------------------------------------------
-- Usuarios: 1 administrador, 2 recepcionistas e 12 clientes
-- -----------------------------------------------------------------------------
INSERT INTO usuario (id_usuario, nome, cpf, email, telefone, senha_hash, perfil, aceite_lgpd, criado_em) VALUES
( 1, 'Mariana Costa',       '10433218100', 'mariana.costa@exemplo.com.br',   '11987650001', '$2b$12$2edlBDdz1C5Jau2RJtBRnlWmTSHf6pWkLUyifDLkDmWJ6UuVTAIjv', 'ADMIN',    NOW() - INTERVAL 120 DAY, NOW() - INTERVAL 120 DAY),
( 2, 'Paulo Henrique Dias', '83276483572', 'paulo.dias@exemplo.com.br',      '11987650002', '$2b$12$hDeOZIiBOB/Y6sHrFH2ZUCr/lgotu2iXW7GboIRoL3u6aHwnMztVu', 'RECEPCAO', NOW() - INTERVAL 118 DAY, NOW() - INTERVAL 118 DAY),
( 3, 'Juliana Prado',       '88095701548', 'juliana.prado@exemplo.com.br',   '11987650003', '$2b$12$NEhEkk.iqq8vH2BzNZV45pFCiRcDCajhDieQjEJ.Bq8F80ymm3T20', 'RECEPCAO', NOW() - INTERVAL 118 DAY, NOW() - INTERVAL 118 DAY),
( 4, 'Lucas Ferreira',      '70106513370', 'lucas.ferreira@exemplo.com.br',  '11976540004', '$2b$12$y5r2xJ7Fj4mgblEv0.9BZhvWaXH6K2.tyLBhhOhg9uhkxiiEZpFfk', 'CLIENTE',  NOW() - INTERVAL 100 DAY, NOW() - INTERVAL 100 DAY),
( 5, 'Bruno Almeida',       '69985435303', 'bruno.almeida@exemplo.com.br',   '11976540005', '$2b$12$HYqM6Ojb6mjBHqSiFVKu4MbMnrHontIKARAH.Ggl2JfaQqHu42boj', 'CLIENTE',  NOW() - INTERVAL 95 DAY,  NOW() - INTERVAL 95 DAY),
( 6, 'Camila Rodrigues',    '28059826220', 'camila.rodrigues@exemplo.com.br','11976540006', '$2b$12$fNUfTAFnT0tEuw0dwQ0FIunWe8Cz6SNDCdyZQJiJSZQdoHwHen3SO', 'CLIENTE',  NOW() - INTERVAL 90 DAY,  NOW() - INTERVAL 90 DAY),
( 7, 'Diego Martins',       '69816934027', 'diego.martins@exemplo.com.br',   '11976540007', '$2b$12$3azU3iQOpMN0PZLqy1WwMZaMKA3P744B8vkKQlENCzsdfF8j61yX/', 'CLIENTE',  NOW() - INTERVAL 88 DAY,  NOW() - INTERVAL 88 DAY),
( 8, 'Fernanda Lima',       '63201632830', 'fernanda.lima@exemplo.com.br',   '11976540008', '$2b$12$7gFp6r7O425u85HFJ.EJ4jKEIQOkrtDXtBi10Q71hA1XcW9aTMX1C', 'CLIENTE',  NOW() - INTERVAL 80 DAY,  NOW() - INTERVAL 80 DAY),
( 9, 'Gabriel Souza',       '73467065600', 'gabriel.souza@exemplo.com.br',   '11976540009', '$2b$12$v7qdYdk2r7xgHWPB6PRWJ1Gk8cgSCifdFzctEq8oB7GVvouNndNWY', 'CLIENTE',  NOW() - INTERVAL 95 DAY,  NOW() - INTERVAL 95 DAY),
(10, 'Thiago Oliveira',     '31931491950', 'thiago.oliveira@exemplo.com.br', '11976540010', '$2b$12$fS2ViRb1.n3U6t3wI973IPFlJ5F7WRd/Px.BTHRJJbykE0.E8.5cl', 'CLIENTE',  NOW() - INTERVAL 70 DAY,  NOW() - INTERVAL 70 DAY),
(11, 'Patricia Gomes',      '43634957824', 'patricia.gomes@exemplo.com.br',  '11976540011', '$2b$12$S2QT6INGDpyOpxyB9JKmyLDUwMbqJfgLq.nbK894RxgG9oiZ.jgtt', 'CLIENTE',  NOW() - INTERVAL 60 DAY,  NOW() - INTERVAL 60 DAY),
(12, 'Eduardo Barbosa',     '94131869950', 'eduardo.barbosa@exemplo.com.br', '11976540012', '$2b$12$CW54M2NhmABHkuEwjua058LeDKK6jDHz2oCtIsjhvNK4p7MZI/4kf', 'CLIENTE',  NOW() - INTERVAL 55 DAY,  NOW() - INTERVAL 55 DAY),
(13, 'Larissa Mendes',      '65940139981', 'larissa.mendes@exemplo.com.br',  '11976540013', '$2b$12$cIfw84Jx3.l8S0QPnuQ0/KZe6lOGPoZa70gyU/4gAIqK4.pdEuNb0', 'CLIENTE',  NOW() - INTERVAL 50 DAY,  NOW() - INTERVAL 50 DAY),
(14, 'Vinicius Carvalho',   '13171274809', 'vinicius.carvalho@exemplo.com.br','11976540014','$2b$12$I198F6sXyriJ1RIaKM.t59SQW6PyEXD0fO8WXt/eqQm4m6bs0tj8H', 'CLIENTE',  NOW() - INTERVAL 40 DAY,  NOW() - INTERVAL 40 DAY),
-- cliente que se cadastrou pela recepcao e ainda nao aceitou os termos no app
(15, 'Aline Ribeiro',       '59615865702', 'aline.ribeiro@exemplo.com.br',   '11976540015', '$2b$12$eiEKDl3mm4vMdfPhLTV3sF0xvwkWE/sD7G6Gb7Kuj4SM2G6MzX9nE', 'CLIENTE',  NULL,                     NOW() - INTERVAL 35 DAY);


-- -----------------------------------------------------------------------------
-- Modalidades. O enunciado do PIM cita 4 esportes "principais", mas a
-- poliesportiva tambem recebe basquete e a de areia tambem recebe futevolei;
-- por isso sao 6 modalidades.
-- -----------------------------------------------------------------------------
INSERT INTO modalidade (id_modalidade, nome) VALUES
(1, 'Futebol society'),
(2, 'Futsal'),
(3, 'Volei'),
(4, 'Basquete'),
(5, 'Beach tennis'),
(6, 'Futevolei');


-- -----------------------------------------------------------------------------
-- Quadras da Arena Meio-Campo
-- -----------------------------------------------------------------------------
INSERT INTO quadra (id_quadra, nome, tipo_piso, coberta, capacidade, ativa) VALUES
(1, 'Society 1',     'grama sintetica', FALSE, 14, TRUE),
(2, 'Society 2',     'grama sintetica', FALSE, 14, TRUE),
(3, 'Futsal',        'madeira',         TRUE,  10, TRUE),
(4, 'Poliesportiva', 'poliuretano',     TRUE,  12, TRUE),
(5, 'Areia',         'areia',           FALSE,  8, TRUE);

INSERT INTO quadra_modalidade (id_quadra, id_modalidade) VALUES
(1, 1),
(2, 1),
(3, 2),
(4, 3), (4, 4),
(5, 5), (5, 6);


-- -----------------------------------------------------------------------------
-- Horario de funcionamento: todos os dias 08h-23h; a quadra de areia fecha
-- as 22h (iluminacao insuficiente) - ultimo inicio 21h.
-- Gera 5 quadras x 7 dias = 35 linhas a partir de uma lista de dias.
-- -----------------------------------------------------------------------------
INSERT INTO horario_funcionamento (id_quadra, dia_semana, hora_abertura, hora_fechamento)
WITH RECURSIVE dias (d) AS (
    SELECT 1 UNION ALL SELECT d + 1 FROM dias WHERE d < 7
)
SELECT q.id_quadra,
       dias.d,
       '08:00:00',
       CASE WHEN q.id_quadra = 5 THEN '22:00:00' ELSE '23:00:00' END
FROM quadra q
CROSS JOIN dias;


-- -----------------------------------------------------------------------------
-- Tabela de precos (preco dinamico)
--   Dia util (seg-sex, dia_semana 2-6): faixa normal 08h-17h e pico 17h-fechamento
--   Fim de semana (dom=1, sab=7): faixa unica o dia inteiro
-- Valores em reais por hora.
-- -----------------------------------------------------------------------------
INSERT INTO tabela_preco (id_quadra, dia_semana, hora_inicio, hora_fim, valor_hora)
WITH RECURSIVE dias (d) AS (
    SELECT 1 UNION ALL SELECT d + 1 FROM dias WHERE d < 7
),
precos (id_quadra, normal, pico, fim_semana, fecha) AS (
    SELECT 1, 150.00, 220.00, 200.00, '23:00:00' UNION ALL
    SELECT 2, 150.00, 220.00, 200.00, '23:00:00' UNION ALL
    SELECT 3, 130.00, 180.00, 160.00, '23:00:00' UNION ALL
    SELECT 4, 100.00, 140.00, 120.00, '23:00:00' UNION ALL
    SELECT 5,  90.00, 120.00, 110.00, '22:00:00'
)
-- dias uteis, faixa normal
SELECT p.id_quadra, dias.d, '08:00:00', '17:00:00', p.normal
FROM precos p CROSS JOIN dias WHERE dias.d BETWEEN 2 AND 6
UNION ALL
-- dias uteis, horario de pico
SELECT p.id_quadra, dias.d, '17:00:00', p.fecha, p.pico
FROM precos p CROSS JOIN dias WHERE dias.d BETWEEN 2 AND 6
UNION ALL
-- sabado e domingo
SELECT p.id_quadra, dias.d, '08:00:00', p.fecha, p.fim_semana
FROM precos p CROSS JOIN dias WHERE dias.d IN (1, 7);


-- -----------------------------------------------------------------------------
-- Reservas (42): 26 passadas, 4 de hoje e 12 futuras.
-- Primeiro os dados vao para uma tabela temporaria com o deslocamento em dias
-- (dias = -21 significa "21 dias atras"); depois o INSERT ... SELECT calcula a
-- data real, a hora de fim e o valor pela tabela_preco.
-- -----------------------------------------------------------------------------
CREATE TEMPORARY TABLE tmp_reserva (
    id     INT, usuario INT, quadra INT, modalidade INT,
    dias   INT, hora TIME, status VARCHAR(10)
);

INSERT INTO tmp_reserva VALUES
-- ---- passadas -----------------------------------------------------------
( 1,  4, 1, 1, -21, '19:00', 'CONCLUIDA'),   -- Lucas, horario de mensalista
( 2,  5, 1, 1, -21, '20:00', 'CONCLUIDA'),
( 3,  6, 3, 2, -20, '18:00', 'CONCLUIDA'),
( 4,  7, 5, 5, -20, '09:00', 'CONCLUIDA'),
( 5,  8, 4, 3, -19, '19:00', 'CONCLUIDA'),
( 6,  9, 2, 1, -18, '21:00', 'NO_SHOW'),     -- Gabriel: 1o no-show
( 7, 10, 1, 1, -17, '19:00', 'CONCLUIDA'),
( 8, 11, 5, 6, -16, '17:00', 'CONCLUIDA'),
( 9, 12, 3, 2, -15, '20:00', 'CONCLUIDA'),
(10,  9, 1, 1, -14, '22:00', 'NO_SHOW'),     -- Gabriel: 2o no-show
(11,  4, 1, 1, -14, '19:00', 'CONCLUIDA'),
(12, 13, 4, 4, -13, '18:00', 'CONCLUIDA'),
(13, 14, 2, 1, -12, '20:00', 'CANCELADA'),
(14, 15, 5, 5, -11, '08:00', 'CONCLUIDA'),
(15,  6, 3, 2, -10, '19:00', 'CONCLUIDA'),
(16,  7, 5, 5,  -9, '10:00', 'CONCLUIDA'),
(17, 10, 2, 1,  -8, '21:00', 'NO_SHOW'),     -- Thiago: 1 no-show
(18,  4, 1, 1,  -7, '19:00', 'CONCLUIDA'),
(19,  5, 1, 1,  -7, '20:00', 'CONCLUIDA'),
(20,  9, 3, 2,  -6, '19:00', 'NO_SHOW'),     -- Gabriel: 3o no-show
(21,  8, 4, 3,  -5, '20:00', 'CONCLUIDA'),   -- Fernanda, mensalista
(22, 12, 2, 1,  -4, '19:00', 'CONCLUIDA'),
(23, 11, 5, 6,  -3, '16:00', 'CONCLUIDA'),
(24, 13, 4, 4,  -2, '18:00', 'CANCELADA'),
(25, 14, 1, 1,  -1, '21:00', 'CONCLUIDA'),
(26, 15, 3, 2,  -1, '20:00', 'CONCLUIDA'),
-- ---- hoje (aparecem em vw_agenda_do_dia) --------------------------------
(27,  4, 1, 1,   0, '19:00', 'CONFIRMADA'),  -- mensalista do dia
(28,  5, 2, 1,   0, '20:00', 'CONFIRMADA'),
(29,  6, 3, 2,   0, '21:00', 'PENDENTE'),
(30,  8, 4, 3,   0, '19:00', 'CONFIRMADA'),
-- ---- futuras ------------------------------------------------------------
(31,  7, 5, 5,   1, '09:00', 'CONFIRMADA'),
(32, 10, 1, 1,   2, '19:00', 'CONFIRMADA'),  -- tem lista de espera (usado no 05)
(33, 12, 2, 1,   2, '20:00', 'PENDENTE'),
(34, 13, 4, 4,   3, '18:00', 'CONFIRMADA'),
(35, 14, 3, 2,   3, '21:00', 'CONFIRMADA'),  -- tem lista de espera
(36, 15, 5, 6,   4, '17:00', 'PENDENTE'),
(37,  5, 1, 1,   5, '20:00', 'CONFIRMADA'),
(38,  4, 1, 1,   7, '19:00', 'CONFIRMADA'),
(39,  6, 3, 2,   8, '19:00', 'CANCELADA'),
(40,  8, 4, 3,   9, '20:00', 'PENDENTE'),
(41, 11, 5, 5,  10, '10:00', 'CONFIRMADA'),
(42,  4, 1, 1,  14, '19:00', 'PENDENTE');

INSERT INTO reserva (id_reserva, id_usuario, id_quadra, id_modalidade, data_reserva,
                     hora_inicio, hora_fim, status, valor_total, criado_em)
SELECT t.id,
       t.usuario,
       t.quadra,
       t.modalidade,
       CURDATE() + INTERVAL t.dias DAY,
       t.hora,
       ADDTIME(t.hora, '01:00:00'),
       t.status,
       -- preco da faixa [hora_inicio, hora_fim) daquele dia da semana
       (SELECT tp.valor_hora
          FROM tabela_preco tp
         WHERE tp.id_quadra  = t.quadra
           AND tp.dia_semana = DAYOFWEEK(CURDATE() + INTERVAL t.dias DAY)
           AND t.hora >= tp.hora_inicio
           AND t.hora <  tp.hora_fim),
       -- reserva criada 3 dias antes do jogo (ou ha 2 horas, se isso for antes)
       LEAST(NOW() - INTERVAL 2 HOUR,
             TIMESTAMP(CURDATE() + INTERVAL t.dias DAY, t.hora) - INTERVAL 3 DAY)
FROM tmp_reserva t
ORDER BY t.id;

DROP TEMPORARY TABLE tmp_reserva;


-- -----------------------------------------------------------------------------
-- Racha dividido: 5 reservas com o valor dividido igualmente entre amigos.
-- A cota e valor_total / quantidade de participantes (os precos foram
-- escolhidos para a divisao ser exata em centavos).
-- -----------------------------------------------------------------------------
CREATE TEMPORARY TABLE tmp_racha (id_reserva INT, id_usuario INT, pago BOOLEAN);

INSERT INTO tmp_racha VALUES
-- reserva 1 (concluida): todos pagaram
( 1,  4, TRUE), ( 1,  5, TRUE), ( 1, 10, TRUE), ( 1, 14, TRUE),
-- reserva 7 (concluida): todos pagaram
( 7, 10, TRUE), ( 7,  9, TRUE), ( 7, 12, TRUE), ( 7,  7, TRUE),
-- reserva 27 (hoje): metade pagou
(27,  4, TRUE), (27,  5, TRUE), (27, 10, FALSE), (27, 14, FALSE),
-- reserva 28 (hoje): 5 amigos, 3 pagaram
(28,  5, TRUE), (28,  6, TRUE), (28,  7, TRUE), (28,  8, FALSE), (28,  9, FALSE),
-- reserva 37 (futura): 2 de 4 pagaram
(37,  5, TRUE), (37,  4, TRUE), (37, 13, FALSE), (37, 15, FALSE);

INSERT INTO participante_reserva (id_reserva, id_usuario, valor_cota, status_pagamento, pago_em)
SELECT t.id_reserva,
       t.id_usuario,
       -- COUNT(*) OVER: conta os participantes da mesma reserva (funcao de janela;
       -- o MySQL nao deixa ler a mesma tabela temporaria duas vezes na consulta)
       r.valor_total / COUNT(*) OVER (PARTITION BY t.id_reserva),
       CASE WHEN t.pago THEN 'PAGO' ELSE 'PENDENTE' END,
       CASE WHEN t.pago THEN r.criado_em + INTERVAL 1 HOUR ELSE NULL END
FROM tmp_racha t
JOIN reserva r ON r.id_reserva = t.id_reserva;

DROP TEMPORARY TABLE tmp_racha;


-- -----------------------------------------------------------------------------
-- Pagamentos
-- Regra da arena: sinal de 50% via Pix confirma a reserva; o restante e pago
-- no balcao (cartao ou dinheiro) no dia do jogo. No-show perde o sinal;
-- cancelamento devolve o sinal (ESTORNADO).
-- Reservas com racha: cada cota paga vira um pagamento Pix individual.
-- -----------------------------------------------------------------------------

-- (a) cotas do racha ja pagas
INSERT INTO pagamento (id_reserva, forma, valor, status, pago_em, criado_em)
SELECT pr.id_reserva, 'PIX', pr.valor_cota, 'APROVADO', pr.pago_em, pr.pago_em - INTERVAL 2 MINUTE
FROM participante_reserva pr
WHERE pr.status_pagamento = 'PAGO'
ORDER BY pr.id_reserva, pr.pago_em;

-- (b) sinal de 50% das reservas sem racha
INSERT INTO pagamento (id_reserva, forma, valor, status, pago_em, criado_em)
SELECT r.id_reserva,
       'PIX',
       ROUND(r.valor_total / 2, 2),
       CASE WHEN r.status = 'CANCELADA' THEN 'ESTORNADO' ELSE 'APROVADO' END,
       r.criado_em + INTERVAL 10 MINUTE,
       r.criado_em + INTERVAL 5 MINUTE
FROM reserva r
WHERE r.status IN ('CONFIRMADA', 'CONCLUIDA', 'NO_SHOW', 'CANCELADA')
  AND r.id_reserva NOT IN (SELECT id_reserva FROM participante_reserva)
ORDER BY r.id_reserva;

-- (c) restante pago no balcao, na hora do jogo, para as concluidas sem racha
INSERT INTO pagamento (id_reserva, forma, valor, status, pago_em, criado_em)
SELECT r.id_reserva,
       CASE WHEN r.id_reserva % 2 = 0 THEN 'CARTAO' ELSE 'DINHEIRO' END,
       r.valor_total - ROUND(r.valor_total / 2, 2),
       'APROVADO',
       TIMESTAMP(r.data_reserva, r.hora_inicio),
       TIMESTAMP(r.data_reserva, r.hora_inicio)
FROM reserva r
WHERE r.status = 'CONCLUIDA'
  AND r.id_reserva NOT IN (SELECT id_reserva FROM participante_reserva)
ORDER BY r.id_reserva;

-- (d) reservas PENDENTES: Pix gerado e ainda nao pago
INSERT INTO pagamento (id_reserva, forma, valor, status, pago_em, criado_em)
SELECT r.id_reserva, 'PIX', ROUND(r.valor_total / 2, 2), 'PENDENTE', NULL, r.criado_em + INTERVAL 1 MINUTE
FROM reserva r
WHERE r.status = 'PENDENTE'
ORDER BY r.id_reserva;


-- -----------------------------------------------------------------------------
-- Lista de espera: horarios disputados que ja estao ocupados
--   reserva 32 (Society 1, daqui a 2 dias, 19h): Patricia e Eduardo esperando
--   reserva 35 (Futsal, daqui a 3 dias, 21h): Gabriel esperando
-- -----------------------------------------------------------------------------
INSERT INTO lista_espera (id_usuario, id_quadra, data_reserva, hora_inicio, posicao, criado_em) VALUES
(11, 1, CURDATE() + INTERVAL 2 DAY, '19:00', 1, NOW() - INTERVAL 30 HOUR),
(12, 1, CURDATE() + INTERVAL 2 DAY, '19:00', 2, NOW() - INTERVAL 20 HOUR),
( 9, 3, CURDATE() + INTERVAL 3 DAY, '21:00', 1, NOW() - INTERVAL 5 HOUR);


-- -----------------------------------------------------------------------------
-- Mensalistas
--   Lucas: Society 1, toda semana no mesmo dia da semana de hoje, 19h
--   Fernanda: Poliesportiva (volei), 20h
--   Gabriel: ex-mensalista, desligado depois dos no-shows (historico)
-- -----------------------------------------------------------------------------
INSERT INTO mensalista (id_usuario, id_quadra, dia_semana, hora_inicio, data_inicio, data_fim, ativo) VALUES
( 4, 1, DAYOFWEEK(CURDATE()),                    '19:00', CURDATE() - INTERVAL 60 DAY, NULL,                        TRUE),
( 8, 4, DAYOFWEEK(CURDATE() - INTERVAL 5 DAY),   '20:00', CURDATE() - INTERVAL 45 DAY, NULL,                        TRUE),
( 9, 2, DAYOFWEEK(CURDATE() - INTERVAL 18 DAY),  '21:00', CURDATE() - INTERVAL 90 DAY, CURDATE() - INTERVAL 10 DAY, FALSE);


-- -----------------------------------------------------------------------------
-- Avaliacoes (somente de reservas CONCLUIDAS)
-- -----------------------------------------------------------------------------
INSERT INTO avaliacao (id_reserva, nota, comentario, criado_em)
SELECT v.id_reserva, v.nota, v.comentario,
       TIMESTAMP(r.data_reserva, r.hora_fim) + INTERVAL 2 HOUR
FROM (
    SELECT  1 AS id_reserva, 5 AS nota, 'Grama nova, otima iluminacao.' AS comentario UNION ALL
    SELECT  2, 4, 'Muito boa, so faltou bola reserva.'                  UNION ALL
    SELECT  3, 4, 'Piso excelente.'                                     UNION ALL
    SELECT  4, 5, 'Areia bem cuidada, rede nova.'                       UNION ALL
    SELECT  5, 3, 'Rede do volei estava frouxa.'                        UNION ALL
    SELECT  7, 5, NULL                                                  UNION ALL
    SELECT  8, 4, 'Bom, mas fecha cedo.'                                UNION ALL
    SELECT  9, 2, 'Vestiario sujo e chuveiro frio.'                     UNION ALL
    SELECT 11, 5, 'Recepcao rapida, tudo certo.'                        UNION ALL
    SELECT 12, 4, 'Cesta nova, piso bom.'                               UNION ALL
    SELECT 14, 5, 'Melhor quadra de beach tennis da regiao.'            UNION ALL
    SELECT 15, 3, 'Quadra boa, mas atrasaram 10 minutos para liberar.'  UNION ALL
    SELECT 16, 4, NULL                                                  UNION ALL
    SELECT 18, 5, 'Sempre impecavel.'                                   UNION ALL
    SELECT 21, 4, 'Boa, iluminacao poderia melhorar.'                   UNION ALL
    SELECT 22, 3, 'Gramado gasto perto do gol.'                         UNION ALL
    SELECT 23, 5, NULL                                                  UNION ALL
    SELECT 25, 4, 'Tranquilo.'
) v
JOIN reserva r ON r.id_reserva = v.id_reserva;


-- -----------------------------------------------------------------------------
-- Log de auditoria: alguns registros historicos (os triggers do script 03
-- ainda nao existem nesta etapa; a partir dele o log e automatico).
-- -----------------------------------------------------------------------------
INSERT INTO log_auditoria (tabela, id_registro, acao, id_usuario, data_hora, detalhes)
SELECT 'reserva', r.id_reserva, 'STATUS',
       CASE WHEN r.status = 'NO_SHOW' THEN 2 ELSE r.id_usuario END,  -- no-show e marcado pela recepcao
       CASE WHEN r.status = 'NO_SHOW' THEN TIMESTAMP(r.data_reserva, r.hora_fim)
            ELSE LEAST(NOW() - INTERVAL 1 HOUR, r.criado_em + INTERVAL 1 DAY) END,
       JSON_OBJECT('de', 'CONFIRMADA', 'para', r.status)
FROM reserva r
WHERE r.status IN ('CANCELADA', 'NO_SHOW')
ORDER BY r.id_reserva;
