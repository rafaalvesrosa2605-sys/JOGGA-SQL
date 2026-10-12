-- =============================================================
-- JOGGA - Testes das regras do banco
-- Rode DEPOIS do jogga.sql.
-- Execute UM comando de cada vez (cursor na linha + Ctrl+Enter).
-- Os 4 primeiros DEVEM dar erro: e o banco protegendo os dados.
-- =============================================================
USE jogga;

-- TESTE 1 - Conflito de horario: a Society 1 ja esta reservada
-- em 22/10 as 19h (reserva 18).
-- ESPERADO: erro "Duplicate entry ... for key uk_horario"
INSERT INTO reserva (id_usuario, id_quadra, id_modalidade, data_reserva, hora_inicio, valor)
VALUES (5, 1, 1, '2026-10-22', '19:00', 180.00);

-- TESTE 2 - Nota fora da faixa 1 a 5.
-- ESPERADO: erro "Check constraint ck_nota is violated"
INSERT INTO avaliacao (id_reserva, nota) VALUES (14, 6);

-- TESTE 3 - Reserva as 23h (o ultimo horario e 22h).
-- ESPERADO: erro "Check constraint ck_horario is violated"
INSERT INTO reserva (id_usuario, id_quadra, id_modalidade, data_reserva, hora_inicio, valor)
VALUES (5, 2, 1, '2026-10-30', '23:00', 180.00);

-- TESTE 4 - Apagar uma quadra que esta em uso (tem reservas e modalidades).
-- As chaves estrangeiras impedem: os registros ligados a ela ficariam orfaos.
-- ESPERADO: erro "Cannot delete or update a parent row"
DELETE FROM quadra WHERE id_quadra = 1;

-- TESTE 5 - DEVE FUNCIONAR: reservar o horario de uma reserva cancelada.
-- A reserva 10 (Poliesportiva, 12/10 as 18h) foi cancelada,
-- entao o horario esta livre de novo.
INSERT INTO reserva (id_usuario, id_quadra, id_modalidade, data_reserva, hora_inicio, status, valor)
VALUES (7, 4, 3, '2026-10-12', '18:00', 'CONCLUIDA', 120.00);

-- As duas reservas no mesmo horario: a cancelada (hora_ocupada NULL) e a nova
SELECT id_reserva, data_reserva, hora_inicio, status, hora_ocupada
  FROM reserva
 WHERE id_quadra = 4 AND data_reserva = '2026-10-12';
