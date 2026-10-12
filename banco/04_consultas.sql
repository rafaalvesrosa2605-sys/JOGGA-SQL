-- =============================================================================
-- JOGGA - Script 04: principais consultas (para a apresentacao)
-- Pre-requisitos: scripts 01, 02 e 03.
--
-- As consultas usam variaveis de sessao (@quadra, @data, @cliente) para que o
-- grupo troque o parametro durante a apresentacao sem editar o SQL.
-- [PG] variaveis @x nao existem: usar valores fixos ou \set no psql.
-- No fim ha exemplos de INSERT, UPDATE e DELETE dentro de uma transacao com
-- ROLLBACK, para nao alterar os dados usados pelo 05_testes.sql.
-- =============================================================================

SET NAMES utf8mb4;   -- comunicacao em UTF-8, independente do terminal
USE jogga;

-- -----------------------------------------------------------------------------
-- Q1. Horarios LIVRES de uma quadra em uma data (RF02 - agenda_horarios_livres)
-- Gera as horas 08h..22h, mantem so as que cabem no funcionamento da quadra
-- naquele dia e tira as ocupadas por reserva ativa ou por mensalista.
-- Ja mostra o preco de cada horario (preco dinamico).
-- Exemplo: Society 1 daqui a 2 dias -> 19h nao aparece (reserva 32).
-- -----------------------------------------------------------------------------
SET @quadra = 1;
SET @data   = CURDATE() + INTERVAL 2 DAY;

WITH RECURSIVE horas (h) AS (
    SELECT CAST('08:00:00' AS TIME)
    UNION ALL
    SELECT ADDTIME(h, '01:00:00') FROM horas WHERE h < '22:00:00'
)
SELECT @data                         AS data,
       TIME_FORMAT(hs.h, '%H:%i')    AS horario_livre,
       fn_valor_hora(@quadra, @data, hs.h) AS valor_hora
  FROM horas hs
  JOIN horario_funcionamento hf
    ON hf.id_quadra  = @quadra
   AND hf.dia_semana = DAYOFWEEK(@data)
   AND hs.h >= hf.hora_abertura
   AND ADDTIME(hs.h, '01:00:00') <= hf.hora_fechamento
 WHERE NOT EXISTS (SELECT 1 FROM reserva r              -- reserva ativa no horario
                    WHERE r.id_quadra    = @quadra
                      AND r.data_reserva = @data
                      AND r.hora_inicio  = hs.h
                      AND r.status      <> 'CANCELADA')
   AND NOT EXISTS (SELECT 1 FROM mensalista ms          -- horario fixo de mensalista
                    WHERE ms.id_quadra   = @quadra
                      AND ms.dia_semana  = DAYOFWEEK(@data)
                      AND ms.hora_inicio = hs.h
                      AND ms.ativo
                      AND @data >= ms.data_inicio
                      AND (ms.data_fim IS NULL OR @data <= ms.data_fim))
 ORDER BY hs.h;


-- -----------------------------------------------------------------------------
-- Q2. Faturamento por mes e por quadra (pagamentos aprovados)
-- WITH ROLLUP acrescenta as linhas de subtotal do mes e o total geral
-- (aparecem com quadra = NULL; o COALESCE troca por um rotulo).
-- [PG] GROUP BY ROLLUP (mes, quadra).
-- -----------------------------------------------------------------------------
SELECT COALESCE(mes, 'TOTAL GERAL')                              AS mes,
       CASE WHEN mes IS NULL THEN ''
            ELSE COALESCE(quadra, '-- subtotal do mes') END      AS quadra,
       SUM(faturamento)                                          AS faturamento
  FROM vw_faturamento_mensal
 GROUP BY mes, quadra WITH ROLLUP;


-- -----------------------------------------------------------------------------
-- Q3. Horario de pico: quantas reservas (nao canceladas) por hora do dia
-- Mostra ao gestor onde vale cobrar mais caro e onde criar promocao.
-- -----------------------------------------------------------------------------
SELECT TIME_FORMAT(hora_inicio, '%H:%i')                AS horario,
       COUNT(*)                                         AS reservas,
       RPAD('', COUNT(*), '#')                          AS grafico
  FROM reserva
 WHERE status <> 'CANCELADA'
 GROUP BY hora_inicio
 ORDER BY reservas DESC, hora_inicio;

-- Q3b. Pico por dia da semana (ELT converte 1..7 no nome do dia)
-- (a subconsulta calcula o numero do dia antes; o modo ONLY_FULL_GROUP_BY do
--  MySQL exige que o SELECT use exatamente a coluna agrupada)
SELECT ELT(d.dia, 'domingo', 'segunda', 'terca', 'quarta',
                  'quinta', 'sexta', 'sabado')  AS dia_semana,
       COUNT(*)                                 AS reservas
  FROM (SELECT DAYOFWEEK(data_reserva) AS dia
          FROM reserva
         WHERE status <> 'CANCELADA') d
 GROUP BY d.dia
 ORDER BY reservas DESC, d.dia;


-- -----------------------------------------------------------------------------
-- Q4. Clientes com mais no-show (faltaram sem cancelar)
-- taxa = no-shows / reservas que ja aconteceram (concluidas + no-show).
-- HAVING filtra depois do agrupamento (WHERE filtra antes).
-- -----------------------------------------------------------------------------
SELECT u.nome,
       u.telefone,
       SUM(r.status = 'NO_SHOW')                                  AS no_shows,
       SUM(r.status IN ('CONCLUIDA', 'NO_SHOW'))                  AS jogos_passados,
       ROUND(100 * SUM(r.status = 'NO_SHOW')
                 / SUM(r.status IN ('CONCLUIDA', 'NO_SHOW')), 1)  AS taxa_no_show_pct
  FROM usuario u
  JOIN reserva r ON r.id_usuario = u.id_usuario
 GROUP BY u.id_usuario, u.nome, u.telefone
HAVING no_shows > 0
 ORDER BY no_shows DESC, taxa_no_show_pct DESC;
-- [PG] SUM(condicao) nao funciona: usar COUNT(*) FILTER (WHERE r.status = 'NO_SHOW').


-- -----------------------------------------------------------------------------
-- Q5. Ranking das quadras pela nota media das avaliacoes
-- RANK() e uma funcao de janela: numera as linhas pela ordem da media.
-- LEFT JOIN para quadra sem avaliacao tambem aparecer (com media NULL).
-- -----------------------------------------------------------------------------
SELECT RANK() OVER (ORDER BY AVG(a.nota) DESC) AS posicao,
       q.nome                                  AS quadra,
       ROUND(AVG(a.nota), 2)                   AS nota_media,
       COUNT(a.id_avaliacao)                   AS avaliacoes,
       MIN(a.nota)                             AS pior_nota
  FROM quadra q
  LEFT JOIN reserva   r ON r.id_quadra  = q.id_quadra
  LEFT JOIN avaliacao a ON a.id_reserva = r.id_reserva
 GROUP BY q.id_quadra, q.nome
 ORDER BY posicao;


-- -----------------------------------------------------------------------------
-- Q6. Ocupacao por quadra nos ultimos 30 dias (view)
-- Com os dados de exemplo a taxa e baixa (poucas dezenas de reservas para
-- ~2.200 horas disponiveis); por isso a Q6b olha so o horario nobre.
-- -----------------------------------------------------------------------------
SELECT * FROM vw_ocupacao_por_quadra ORDER BY taxa_ocupacao_pct DESC;

-- Q6b. Ocupacao por quadra no horario nobre (17h-23h) de TODO o periodo com
-- reservas: mostra que a demanda se concentra a noite.
SELECT q.nome                                                          AS quadra,
       SUM(r.status IN ('CONFIRMADA','CONCLUIDA','NO_SHOW')
           AND r.hora_inicio >= '17:00:00')                            AS reservas_noite,
       SUM(r.status IN ('CONFIRMADA','CONCLUIDA','NO_SHOW')
           AND r.hora_inicio <  '17:00:00')                            AS reservas_dia
  FROM quadra q
  LEFT JOIN reserva r ON r.id_quadra = q.id_quadra
 GROUP BY q.id_quadra, q.nome
 ORDER BY reservas_noite DESC;


-- -----------------------------------------------------------------------------
-- Q7. Reservas de um cliente (RF04 - "minhas reservas")
-- -----------------------------------------------------------------------------
SET @cliente = 4;   -- Lucas Ferreira (mensalista)

SELECT r.id_reserva,
       r.data_reserva,
       TIME_FORMAT(r.hora_inicio, '%H:%i')                  AS hora,
       q.nome                                               AS quadra,
       m.nome                                               AS modalidade,
       r.status,
       r.valor_total,
       CASE WHEN r.data_reserva >= CURDATE() THEN 'proxima' ELSE 'historico' END AS quando
  FROM reserva r
  JOIN quadra     q ON q.id_quadra     = r.id_quadra
  JOIN modalidade m ON m.id_modalidade = r.id_modalidade
 WHERE r.id_usuario = @cliente
 ORDER BY r.data_reserva DESC, r.hora_inicio DESC;


-- -----------------------------------------------------------------------------
-- Q8. Quem esta na lista de espera (horarios futuros), por ordem de fila,
-- junto com quem ocupa o horario hoje.
-- -----------------------------------------------------------------------------
SELECT le.data_reserva,
       TIME_FORMAT(le.hora_inicio, '%H:%i')  AS hora,
       q.nome                                AS quadra,
       le.posicao,
       u.nome                                AS na_fila,
       u.telefone,
       le.status,
       dono.nome                             AS horario_ocupado_por
  FROM lista_espera le
  JOIN quadra  q ON q.id_quadra  = le.id_quadra
  JOIN usuario u ON u.id_usuario = le.id_usuario
  LEFT JOIN reserva r  ON r.id_quadra    = le.id_quadra
                      AND r.data_reserva = le.data_reserva
                      AND r.hora_inicio  = le.hora_inicio
                      AND r.status      <> 'CANCELADA'
  LEFT JOIN usuario dono ON dono.id_usuario = r.id_usuario
 WHERE le.data_reserva >= CURDATE()
   AND le.status IN ('AGUARDANDO', 'NOTIFICADO')
 ORDER BY le.data_reserva, le.hora_inicio, q.nome, le.posicao;


-- -----------------------------------------------------------------------------
-- Q9. Racha dividido: quanto falta receber por reserva e de quem
-- GROUP_CONCAT junta os nomes de quem ainda nao pagou em uma so coluna.
-- [PG] GROUP_CONCAT -> string_agg(u.nome, ', ').
-- -----------------------------------------------------------------------------
SELECT r.id_reserva,
       r.data_reserva,
       q.nome                                                         AS quadra,
       r.valor_total,
       COUNT(*)                                                       AS jogadores,
       SUM(CASE WHEN pr.status_pagamento = 'PAGO' THEN pr.valor_cota ELSE 0 END)     AS valor_pago,
       SUM(CASE WHEN pr.status_pagamento = 'PENDENTE' THEN pr.valor_cota ELSE 0 END) AS valor_pendente,
       GROUP_CONCAT(CASE WHEN pr.status_pagamento = 'PENDENTE' THEN u.nome END
                    ORDER BY u.nome SEPARATOR ', ')                   AS devendo
  FROM participante_reserva pr
  JOIN reserva r ON r.id_reserva = pr.id_reserva
  JOIN quadra  q ON q.id_quadra  = r.id_quadra
  JOIN usuario u ON u.id_usuario = pr.id_usuario
 GROUP BY r.id_reserva, r.data_reserva, q.nome, r.valor_total
 ORDER BY valor_pendente DESC, r.data_reserva;


-- -----------------------------------------------------------------------------
-- Q10. Mensalistas ativos (horarios fixos da semana)
-- -----------------------------------------------------------------------------
SELECT u.nome                                                       AS cliente,
       u.telefone,
       q.nome                                                       AS quadra,
       ELT(ms.dia_semana, 'domingo', 'segunda', 'terca', 'quarta',
                          'quinta', 'sexta', 'sabado')              AS dia,
       TIME_FORMAT(ms.hora_inicio, '%H:%i')                         AS hora,
       ms.data_inicio,
       COALESCE(CAST(ms.data_fim AS CHAR), 'sem prazo')             AS ate
  FROM mensalista ms
  JOIN usuario u ON u.id_usuario = ms.id_usuario
  JOIN quadra  q ON q.id_quadra  = ms.id_quadra
 WHERE ms.ativo
   AND (ms.data_fim IS NULL OR ms.data_fim >= CURDATE())
 ORDER BY ms.dia_semana, ms.hora_inicio;


-- -----------------------------------------------------------------------------
-- Q11. Agenda do dia para a recepcao (RF08), com saldo a cobrar no balcao
-- -----------------------------------------------------------------------------
SELECT * FROM vw_agenda_do_dia ORDER BY inicio, quadra;


-- -----------------------------------------------------------------------------
-- Q12. LGPD: clientes sem registro de consentimento (bloquear marketing ate
-- o aceite) e historico de auditoria de uma reserva.
-- -----------------------------------------------------------------------------
SELECT id_usuario, nome, email, criado_em
  FROM usuario
 WHERE aceite_lgpd IS NULL;

SELECT data_hora, acao, id_usuario, detalhes
  FROM log_auditoria
 WHERE tabela = 'reserva' AND id_registro = 6
 ORDER BY data_hora;


-- =============================================================================
-- EXEMPLOS DE INSERT, UPDATE E DELETE
-- Tudo dentro de uma transacao desfeita no fim (ROLLBACK): os comandos
-- executam de verdade (triggers e restricoes rodam), mas o banco volta ao
-- estado anterior. Para gravar de verdade, troque ROLLBACK por COMMIT.
-- (Reservas de verdade devem ser criadas com CALL sp_reservar, que faz o
--  proprio COMMIT - por isso ela fica no 05_testes.sql.)
-- =============================================================================
START TRANSACTION;

SET @id_usuario_app = 2;   -- quem esta operando: Paulo, da recepcao

-- INSERT: novo cliente cadastrado no balcao (hash ficticio)
INSERT INTO usuario (nome, cpf, email, telefone, senha_hash, perfil, aceite_lgpd)
VALUES ('Renata Teixeira', '52998224725', 'renata.teixeira@exemplo.com.br', '11976540016',
        '$2b$12$Qm1f0yQe4rC2l7nV8sXpUOeYb3kZ9tH6wLdA5jR0gM2cN4pS7uV1a', 'CLIENTE', NOW());
SET @nova_cliente = LAST_INSERT_ID();

-- INSERT: reserva para ela (o valor vem da tabela de preco)
INSERT INTO reserva (id_usuario, id_quadra, id_modalidade, data_reserva, hora_inicio, hora_fim, valor_total)
VALUES (@nova_cliente, 4, 3, CURDATE() + INTERVAL 6 DAY, '10:00', '11:00',
        fn_valor_hora(4, CURDATE() + INTERVAL 6 DAY, '10:00'));
SET @nova_reserva = LAST_INSERT_ID();

-- INSERT: ela entra na fila de espera de um horario ocupado (posicao automatica)
INSERT INTO lista_espera (id_usuario, id_quadra, data_reserva, hora_inicio)
VALUES (@nova_cliente, 1, CURDATE() + INTERVAL 2 DAY, '19:00');

-- UPDATE: sinal pago -> reserva confirmada (o trigger grava no log)
INSERT INTO pagamento (id_reserva, forma, valor, status, pago_em)
SELECT id_reserva, 'PIX', valor_total / 2, 'APROVADO', NOW() FROM reserva WHERE id_reserva = @nova_reserva;
UPDATE reserva SET status = 'CONFIRMADA' WHERE id_reserva = @nova_reserva;

-- UPDATE: reajuste de 10% no horario de pico das quadras society
UPDATE tabela_preco
   SET valor_hora = ROUND(valor_hora * 1.10, 2)
 WHERE id_quadra IN (1, 2) AND hora_inicio = '17:00:00';

-- DELETE: cliente desistiu da fila de espera
DELETE FROM lista_espera
 WHERE id_usuario = @nova_cliente AND id_quadra = 1 AND data_reserva = CURDATE() + INTERVAL 2 DAY;

-- conferindo o efeito antes de desfazer
SELECT r.id_reserva, u.nome, r.data_reserva, r.status, r.valor_total
  FROM reserva r JOIN usuario u ON u.id_usuario = r.id_usuario
 WHERE r.id_reserva = @nova_reserva;
SELECT acao, detalhes FROM log_auditoria WHERE tabela = 'reserva' AND id_registro = @nova_reserva;
SELECT dia_semana, hora_inicio, valor_hora FROM tabela_preco
 WHERE id_quadra = 1 AND hora_inicio = '17:00:00' ORDER BY dia_semana;

ROLLBACK;   -- desfaz todos os exemplos acima
