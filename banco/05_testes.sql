-- =============================================================================
-- JOGGA - Script 05: testes das regras garantidas pelo banco
-- Pre-requisitos: scripts 01, 02 e 03 recem-executados (dados originais).
--
-- A primeira parte tem comandos que DEVEM FALHAR: cada erro e a prova de que
-- o banco recusa dados invalidos sozinho, sem depender da aplicacao.
-- A segunda parte tem os comandos que DEVEM PASSAR.
--
-- Como rodar (o script precisa CONTINUAR depois dos erros esperados):
--   linha de comando:  mysql -u root -p --force -v -t < 05_testes.sql
--   MySQL Workbench:   menu Query > desmarcar "Stop Script Execution on Errors"
--                      (ou executar teste por teste com Ctrl+Enter)
--
-- Este script altera dados (cancela a reserva 32 e cria uma nova). Para
-- repetir os testes do zero, rode novamente 01, 02 e 03.
-- =============================================================================

USE jogga;
SET @id_usuario_app = 2;   -- os comandos sao feitos "pela recepcao" (Paulo)


-- #############################################################################
-- PARTE 1 - COMANDOS QUE DEVEM FALHAR
-- #############################################################################

-- -----------------------------------------------------------------------------
-- T01 - Regra principal (RN01): reserva em conflito, INSERT direto.
-- A reserva 27 ja ocupa a Society 1 hoje as 19h.
-- ESPERADO: ERROR 1062 Duplicate entry ... for key 'reserva.uk_reserva_horario'
-- -----------------------------------------------------------------------------
SELECT 'T01 - conflito via INSERT direto (deve falhar: 1062)' AS teste;
INSERT INTO reserva (id_usuario, id_quadra, id_modalidade, data_reserva, hora_inicio, hora_fim, status, valor_total)
VALUES (7, 1, 1, CURDATE(), '19:00', '20:00', 'PENDENTE', 220.00);

-- -----------------------------------------------------------------------------
-- T02 - Regra principal pela procedure: mesma situacao, mensagem amigavel.
-- A reserva 32 ocupa a Society 1 daqui a 2 dias as 19h.
-- ESPERADO: ERROR 1644 'Ja existe agendamento nesta quadra, dia e horario.'
-- -----------------------------------------------------------------------------
SELECT 'T02 - conflito via sp_reservar (deve falhar: 1644)' AS teste;
CALL sp_reservar(7, 1, CURDATE() + INTERVAL 2 DAY, '19:00:00', NULL, @id);

-- -----------------------------------------------------------------------------
-- T03 - Nota fora da faixa 1..5 (reserva 19 esta CONCLUIDA e sem avaliacao,
-- entao o unico motivo da falha e a nota).
-- ESPERADO: ERROR 3819 Check constraint 'ck_avaliacao_nota' is violated
-- -----------------------------------------------------------------------------
SELECT 'T03 - avaliacao com nota 6 (deve falhar: 3819)' AS teste;
INSERT INTO avaliacao (id_reserva, nota, comentario) VALUES (19, 6, 'Nota 6 nao existe');

-- -----------------------------------------------------------------------------
-- T04 - Reserva iniciando as 23h (funcionamento termina as 23h; ultimo
-- inicio 22h). Data futura e quadra livre: so o horario esta errado.
-- hora_fim = '24:00:00' (valor aceito pelo tipo TIME) para que a duracao de
-- 1 hora esteja certa e o UNICO motivo da recusa seja o inicio as 23h.
-- ESPERADO: ERROR 3819 Check constraint 'ck_reserva_inicio' is violated
-- -----------------------------------------------------------------------------
SELECT 'T04 - reserva as 23h via INSERT (deve falhar: 3819)' AS teste;
INSERT INTO reserva (id_usuario, id_quadra, id_modalidade, data_reserva, hora_inicio, hora_fim, status, valor_total)
VALUES (7, 2, 1, CURDATE() + INTERVAL 6 DAY, '23:00', '24:00', 'PENDENTE', 220.00);

-- T04b - o mesmo pedido pela procedure
-- ESPERADO: ERROR 1644 'Horario fora do funcionamento da quadra.'
SELECT 'T04b - reserva as 23h via sp_reservar (deve falhar: 1644)' AS teste;
CALL sp_reservar(7, 2, CURDATE() + INTERVAL 6 DAY, '23:00:00', NULL, @id);

-- -----------------------------------------------------------------------------
-- T05 - Apagar quadra que tem reservas (ON DELETE RESTRICT).
-- Usamos a quadra 5 (Areia): tem reservas, mas nao tem lista de espera nem
-- mensalista, entao quem barra e a FK da RESERVA. (As linhas de
-- quadra_modalidade, horario_funcionamento e tabela_preco seriam apagadas em
-- CASCADE, mas como o comando falha, nada e apagado - e atomico.)
-- ESPERADO: ERROR 1451 ... CONSTRAINT `fk_reserva_quadra...` ...
-- -----------------------------------------------------------------------------
SELECT 'T05 - apagar quadra com reservas (deve falhar: 1451)' AS teste;
DELETE FROM quadra WHERE id_quadra = 5;

-- -----------------------------------------------------------------------------
-- Testes extras das demais regras
-- -----------------------------------------------------------------------------

-- T06 - data no passado (RN05). ESPERADO: 1644 'Data invalida ou no passado...'
SELECT 'T06 - sp_reservar com data no passado (deve falhar: 1644)' AS teste;
CALL sp_reservar(7, 2, CURDATE() - INTERVAL 1 DAY, '10:00:00', NULL, @id);

-- T07 - quadra de areia fecha as 22h: 22h e valido nas outras, mas nao nela.
-- ESPERADO: 1644 'Horario fora do funcionamento da quadra.'
SELECT 'T07 - areia as 22h (deve falhar: 1644)' AS teste;
CALL sp_reservar(7, 5, CURDATE() + INTERVAL 6 DAY, '22:00:00', 5, @id);

-- T08 - modalidade que a quadra nao oferece (beach tennis na quadra de futsal)
-- ESPERADO: ERROR 1452 (FK composta fk_reserva_quadra_modalidade)
SELECT 'T08 - beach tennis na quadra de futsal (deve falhar: 1452)' AS teste;
INSERT INTO reserva (id_usuario, id_quadra, id_modalidade, data_reserva, hora_inicio, hora_fim, status, valor_total)
VALUES (7, 3, 5, CURDATE() + INTERVAL 6 DAY, '10:00', '11:00', 'PENDENTE', 130.00);

-- T09 - horario fixo de mensalista (Lucas, Society 1, mesmo dia da semana de
-- hoje, 19h) pedido por outro cliente daqui a 3 semanas.
-- ESPERADO: 1644 'Horario reservado para um mensalista.'
SELECT 'T09 - horario de mensalista (deve falhar: 1644)' AS teste;
CALL sp_reservar(7, 1, CURDATE() + INTERVAL 21 DAY, '19:00:00', NULL, @id);

-- T10 - avaliar reserva que ainda nao aconteceu (32 esta CONFIRMADA)
-- ESPERADO: 1644 'Somente reservas CONCLUIDAS podem ser avaliadas.'
SELECT 'T10 - avaliar reserva nao concluida (deve falhar: 1644)' AS teste;
INSERT INTO avaliacao (id_reserva, nota) VALUES (32, 5);

-- T11 - reativar reserva cancelada (39) por UPDATE
-- ESPERADO: 1644 'Reserva cancelada nao pode ser reativada...'
SELECT 'T11 - reativar reserva cancelada (deve falhar: 1644)' AS teste;
UPDATE reserva SET status = 'CONFIRMADA' WHERE id_reserva = 39;

-- T12 - reserva quebrada em meia hora (19:30)
-- ESPERADO: 3819 Check constraint 'ck_reserva_hora_cheia' is violated
SELECT 'T12 - reserva as 19:30 (deve falhar: 3819)' AS teste;
INSERT INTO reserva (id_usuario, id_quadra, id_modalidade, data_reserva, hora_inicio, hora_fim, status, valor_total)
VALUES (7, 2, 1, CURDATE() + INTERVAL 6 DAY, '19:30', '20:30', 'PENDENTE', 220.00);

-- conferencia: nenhum dos comandos acima gravou nada
SELECT 'Conferencia: reservas continuam 42 e a quadra 5 continua completa' AS teste;
SELECT (SELECT COUNT(*) FROM reserva)                                AS total_reservas,
       (SELECT COUNT(*) FROM quadra WHERE id_quadra = 5)             AS quadra_5_existe,
       (SELECT COUNT(*) FROM tabela_preco WHERE id_quadra = 5)       AS precos_quadra_5,
       (SELECT COUNT(*) FROM avaliacao)               AS total_avaliacoes;


-- #############################################################################
-- PARTE 2 - COMANDOS QUE DEVEM PASSAR
-- #############################################################################

-- -----------------------------------------------------------------------------
-- P01 - Cancelar a reserva 32 (Society 1, daqui a 2 dias, 19h).
-- ESPERADO: o trigger grava a mudanca de status no log e marca Patricia
-- (1a da fila) como NOTIFICADO; Eduardo (2o) continua AGUARDANDO.
-- -----------------------------------------------------------------------------
SELECT 'P01 - cancelar reserva 32 dispara log e lista de espera (deve passar)' AS teste;
UPDATE reserva SET status = 'CANCELADA' WHERE id_reserva = 32;

SELECT le.posicao, u.nome, le.status, le.notificado_em IS NOT NULL AS foi_notificado
  FROM lista_espera le JOIN usuario u ON u.id_usuario = le.id_usuario
 WHERE le.id_quadra = 1 AND le.data_reserva = CURDATE() + INTERVAL 2 DAY AND le.hora_inicio = '19:00'
 ORDER BY le.posicao;

SELECT tabela, id_registro, acao, id_usuario, detalhes
  FROM log_auditoria
 WHERE (tabela = 'reserva' AND id_registro = 32)
    OR acao = 'NOTIFICAR_ESPERA'
 ORDER BY id_log;

-- -----------------------------------------------------------------------------
-- P02 - Reservar o horario que acabou de ser liberado.
-- Patricia (usuario 11) foi notificada e reserva pela procedure.
-- ESPERADO: sucesso; nova reserva PENDENTE com valor da tabela de preco; a
-- reserva 32 CANCELADA continua no historico no MESMO horario (a coluna
-- hora_bloqueada dela e NULL, por isso o UNIQUE nao reclama); Patricia
-- passa a ATENDIDO na fila.
-- -----------------------------------------------------------------------------
SELECT 'P02 - reservar horario de reserva cancelada (deve passar)' AS teste;
SET @id_usuario_app = 11;
CALL sp_reservar(11, 1, CURDATE() + INTERVAL 2 DAY, '19:00:00', NULL, @nova_reserva);

SELECT @nova_reserva AS id_nova_reserva;

SELECT id_reserva, id_usuario, data_reserva, hora_inicio, status, hora_bloqueada, valor_total
  FROM reserva
 WHERE id_quadra = 1 AND data_reserva = CURDATE() + INTERVAL 2 DAY AND hora_inicio = '19:00'
 ORDER BY id_reserva;

SELECT u.nome, le.status
  FROM lista_espera le JOIN usuario u ON u.id_usuario = le.id_usuario
 WHERE le.id_quadra = 1 AND le.data_reserva = CURDATE() + INTERVAL 2 DAY AND le.hora_inicio = '19:00'
 ORDER BY le.posicao;

-- -----------------------------------------------------------------------------
-- P03 - Depois de P02 o horario esta ocupado de novo: Eduardo (2o da fila)
-- tenta e recebe o erro de conflito. (Este e o unico erro esperado da parte 2.)
-- ESPERADO: 1644 'Ja existe agendamento nesta quadra, dia e horario.'
-- -----------------------------------------------------------------------------
SELECT 'P03 - horario reocupado volta a bloquear (deve falhar: 1644)' AS teste;
CALL sp_reservar(12, 1, CURDATE() + INTERVAL 2 DAY, '19:00:00', NULL, @id);

-- -----------------------------------------------------------------------------
-- P04 - Reserva normal pela procedure, sem informar a modalidade (a Society 2
-- so tem futebol society) e quadra multiuso informando a modalidade.
-- ESPERADO: duas reservas criadas, valores de acordo com o dia/horario.
-- -----------------------------------------------------------------------------
SELECT 'P04 - reservas validas pela procedure (devem passar)' AS teste;
SET @id_usuario_app = 7;
CALL sp_reservar(7, 2, CURDATE() + INTERVAL 6 DAY, '10:00:00', NULL, @r1);
CALL sp_reservar(7, 4, CURDATE() + INTERVAL 6 DAY, '18:00:00', 4, @r2);   -- basquete

SELECT r.id_reserva, q.nome AS quadra, m.nome AS modalidade, r.data_reserva,
       r.hora_inicio, r.status, r.valor_total
  FROM reserva r
  JOIN quadra q     ON q.id_quadra = r.id_quadra
  JOIN modalidade m ON m.id_modalidade = r.id_modalidade
 WHERE r.id_reserva IN (@r1, @r2);

-- resumo final
SELECT 'Resumo: total de reservas apos os testes (42 + 3 = 45)' AS teste;
SELECT status, COUNT(*) AS qtd FROM reserva GROUP BY status ORDER BY status;
