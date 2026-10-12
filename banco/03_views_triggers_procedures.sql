-- =============================================================================
-- JOGGA - Script 03: funcao, views, triggers e stored procedure
-- Pre-requisitos: 01_criacao.sql e 02_dados_exemplo.sql
--
-- Por que colocar regras no banco se o codigo C ja valida?
--   O banco e o unico ponto por onde TODOS os clientes passam (app, painel da
--   recepcao, scripts de importacao). Regra que fica so na aplicacao pode ser
--   esquecida por um deles; regra no banco nao.
--
-- DELIMITER $$: dentro de triggers/procedures existem varios ";". O DELIMITER
-- avisa o cliente (mysql/Workbench) que o comando so termina em "$$".
-- [PG] PostgreSQL nao usa DELIMITER: o corpo vai entre $$ ... $$ e triggers
--      chamam uma FUNCTION ... RETURNS trigger (PL/pgSQL).
-- =============================================================================

SET NAMES utf8mb4;   -- comunicacao em UTF-8, independente do terminal
USE jogga;

DROP VIEW      IF EXISTS vw_agenda_do_dia;
DROP VIEW      IF EXISTS vw_ocupacao_por_quadra;
DROP VIEW      IF EXISTS vw_faturamento_mensal;
DROP TRIGGER   IF EXISTS trg_reserva_ai;
DROP TRIGGER   IF EXISTS trg_reserva_bu;
DROP TRIGGER   IF EXISTS trg_reserva_au;
DROP TRIGGER   IF EXISTS trg_reserva_ad;
DROP TRIGGER   IF EXISTS trg_avaliacao_bi;
DROP TRIGGER   IF EXISTS trg_lista_espera_bi;
DROP PROCEDURE IF EXISTS sp_reservar;
DROP FUNCTION  IF EXISTS fn_valor_hora;


-- =============================================================================
-- FUNCAO fn_valor_hora
-- Devolve o preco da hora de uma quadra em uma data/hora, segundo a
-- tabela_preco (preco dinamico). NULL se nao houver faixa cadastrada.
-- Usada pela sp_reservar e pelas consultas; assim a regra de preco fica
-- escrita em um lugar so.
-- READS SQL DATA: a funcao so le dados (exigencia do MySQL com log binario).
-- =============================================================================
DELIMITER $$
CREATE FUNCTION fn_valor_hora (p_id_quadra SMALLINT UNSIGNED, p_data DATE, p_hora TIME)
RETURNS DECIMAL(8,2)
READS SQL DATA
BEGIN
    DECLARE v_valor DECIMAL(8,2) DEFAULT NULL;

    SELECT tp.valor_hora INTO v_valor
      FROM tabela_preco tp
     WHERE tp.id_quadra  = p_id_quadra
       AND tp.dia_semana = DAYOFWEEK(p_data)
       AND p_hora >= tp.hora_inicio          -- faixa semiaberta [inicio, fim)
       AND p_hora <  tp.hora_fim
     LIMIT 1;

    RETURN v_valor;
END$$
DELIMITER ;


-- =============================================================================
-- VIEWS
-- Uma view e uma consulta salva com nome. A tela/relatorio faz
-- "SELECT * FROM vw_..." sem repetir JOINs, e se a consulta mudar so a view
-- e alterada.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- vw_agenda_do_dia: tudo o que acontece HOJE, para o painel da recepcao
-- (equivale a agenda_do_dia() do codigo C). Mostra quanto ja foi pago e o
-- saldo a cobrar no balcao. Reservas canceladas nao aparecem.
-- -----------------------------------------------------------------------------
CREATE VIEW vw_agenda_do_dia AS
SELECT r.id_reserva,
       r.data_reserva,
       TIME_FORMAT(r.hora_inicio, '%H:%i')               AS inicio,
       TIME_FORMAT(r.hora_fim,    '%H:%i')               AS fim,
       q.nome                                            AS quadra,
       m.nome                                            AS modalidade,
       u.nome                                            AS cliente,
       u.telefone,
       r.status,
       r.valor_total,
       COALESCE(pg.valor_pago, 0)                        AS valor_pago,
       r.valor_total - COALESCE(pg.valor_pago, 0)        AS saldo_a_receber
  FROM reserva r
  JOIN quadra     q ON q.id_quadra     = r.id_quadra
  JOIN modalidade m ON m.id_modalidade = r.id_modalidade
  JOIN usuario    u ON u.id_usuario    = r.id_usuario
  LEFT JOIN (SELECT id_reserva, SUM(valor) AS valor_pago
               FROM pagamento
              WHERE status = 'APROVADO'
              GROUP BY id_reserva) pg ON pg.id_reserva = r.id_reserva
 WHERE r.data_reserva = CURDATE()
   AND r.status <> 'CANCELADA';
-- (ORDER BY fica na consulta que usa a view: SELECT * FROM vw_agenda_do_dia ORDER BY inicio)


-- -----------------------------------------------------------------------------
-- vw_ocupacao_por_quadra: taxa de ocupacao dos ULTIMOS 30 DIAS (ontem para tras).
--   horas_disponiveis = soma, dia a dia, das horas de funcionamento da quadra
--                       (respeita a tabela horario_funcionamento: a de areia
--                       tem 14 h/dia, as demais 15 h/dia);
--   horas_ocupadas    = reservas CONFIRMADA, CONCLUIDA ou NO_SHOW. O no-show
--                       entra porque o horario ficou bloqueado para outros
--                       clientes - e justamente o prejuizo que o gestor quer ver.
--   taxa_ocupacao_pct = ocupadas / disponiveis * 100.
-- O calendario dos 30 dias e gerado por uma CTE recursiva (WITH RECURSIVE).
-- [PG] trocar a CTE por generate_series(CURRENT_DATE - 30, CURRENT_DATE - 1, '1 day').
-- -----------------------------------------------------------------------------
CREATE VIEW vw_ocupacao_por_quadra AS
WITH RECURSIVE calendario (dia) AS (
    SELECT CURDATE() - INTERVAL 30 DAY
    UNION ALL
    SELECT dia + INTERVAL 1 DAY FROM calendario WHERE dia < CURDATE() - INTERVAL 1 DAY
),
disponivel AS (
    SELECT hf.id_quadra,
           SUM(TIMESTAMPDIFF(HOUR, hf.hora_abertura, hf.hora_fechamento)) AS horas
      FROM calendario c
      JOIN horario_funcionamento hf ON hf.dia_semana = DAYOFWEEK(c.dia)
     GROUP BY hf.id_quadra
),
ocupado AS (
    SELECT r.id_quadra, COUNT(*) AS horas          -- cada reserva = 1 hora
      FROM reserva r
     WHERE r.data_reserva BETWEEN CURDATE() - INTERVAL 30 DAY AND CURDATE() - INTERVAL 1 DAY
       AND r.status IN ('CONFIRMADA', 'CONCLUIDA', 'NO_SHOW')
     GROUP BY r.id_quadra
)
SELECT q.id_quadra,
       q.nome                                              AS quadra,
       d.horas                                             AS horas_disponiveis,
       COALESCE(o.horas, 0)                                AS horas_ocupadas,
       ROUND(COALESCE(o.horas, 0) * 100.0 / d.horas, 1)    AS taxa_ocupacao_pct
  FROM quadra q
  JOIN disponivel d    ON d.id_quadra = q.id_quadra
  LEFT JOIN ocupado o  ON o.id_quadra = q.id_quadra
 WHERE q.ativa;


-- -----------------------------------------------------------------------------
-- vw_faturamento_mensal: dinheiro que efetivamente entrou (pagamentos
-- APROVADOS), por mes e por quadra. Pagamento pendente nao e receita e
-- estorno foi devolvido - por isso ficam de fora. O mes e o do pagamento
-- (regime de caixa), nao o da reserva: uma reserva com sinal em um mes e
-- restante no outro conta nos dois meses em reservas_com_pagamento.
-- [PG] DATE_FORMAT(p.pago_em, '%Y-%m') -> to_char(p.pago_em, 'YYYY-MM').
-- -----------------------------------------------------------------------------
CREATE VIEW vw_faturamento_mensal AS
SELECT DATE_FORMAT(p.pago_em, '%Y-%m')   AS mes,
       q.id_quadra,
       q.nome                            AS quadra,
       COUNT(DISTINCT p.id_reserva)      AS reservas_com_pagamento,
       COUNT(*)                          AS qtd_pagamentos,
       SUM(p.valor)                      AS faturamento
  FROM pagamento p
  JOIN reserva r ON r.id_reserva = p.id_reserva
  JOIN quadra  q ON q.id_quadra  = r.id_quadra
 WHERE p.status = 'APROVADO'
 GROUP BY DATE_FORMAT(p.pago_em, '%Y-%m'), q.id_quadra, q.nome;


-- =============================================================================
-- TRIGGERS
-- Um trigger e um bloco executado AUTOMATICAMENTE pelo banco quando ocorre um
-- INSERT/UPDATE/DELETE na tabela. NEW = linha nova; OLD = linha antiga.
-- Quem fez a alteracao vem de @id_usuario_app, variavel de sessao que a
-- aplicacao preenche apos o login (SET @id_usuario_app = <id>).
-- =============================================================================
DELIMITER $$

-- -----------------------------------------------------------------------------
-- Toda reserva criada fica registrada no log (com o status inicial).
-- -----------------------------------------------------------------------------
CREATE TRIGGER trg_reserva_ai
AFTER INSERT ON reserva
FOR EACH ROW
BEGIN
    INSERT INTO log_auditoria (tabela, id_registro, acao, id_usuario, detalhes)
    VALUES ('reserva', NEW.id_reserva, 'INSERT', @id_usuario_app,
            JSON_OBJECT('status', NEW.status, 'id_quadra', NEW.id_quadra,
                        'data', NEW.data_reserva, 'hora', TIME_FORMAT(NEW.hora_inicio, '%H:%i'),
                        'valor_total', NEW.valor_total));
END$$

-- -----------------------------------------------------------------------------
-- Antes de alterar: protege o ciclo de vida do status.
--   * CANCELADA nao volta a ser ativa. Reativar pularia todas as validacoes
--     da sp_reservar (funcionamento, mensalista, preco); o certo e fazer uma
--     nova reserva. (Se outro cliente ja tiver pego o horario, o UNIQUE
--     tambem barraria - mas a mensagem aqui e mais clara.)
--   * CONCLUIDA e NO_SHOW sao finais; so podem trocar entre si, para a
--     recepcao corrigir um registro feito errado.
-- -----------------------------------------------------------------------------
CREATE TRIGGER trg_reserva_bu
BEFORE UPDATE ON reserva
FOR EACH ROW
BEGIN
    IF OLD.status = 'CANCELADA' AND NEW.status <> 'CANCELADA' THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Reserva cancelada nao pode ser reativada. Faca uma nova reserva.';
    END IF;

    IF OLD.status IN ('CONCLUIDA', 'NO_SHOW')
       AND NEW.status NOT IN ('CONCLUIDA', 'NO_SHOW') THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Reserva ja finalizada: so e possivel alternar entre CONCLUIDA e NO_SHOW.';
    END IF;
END$$

-- -----------------------------------------------------------------------------
-- Depois de alterar:
--  (1) grava no log toda mudanca de status (de -> para);
--  (2) se a reserva foi CANCELADA, procura o 1o da lista de espera daquele
--      horario (menor posicao ainda AGUARDANDO), marca como NOTIFICADO e
--      registra no log que ele deve ser avisado. O envio da mensagem em si
--      (push/WhatsApp) e feito pela aplicacao, que le esses registros.
-- -----------------------------------------------------------------------------
CREATE TRIGGER trg_reserva_au
AFTER UPDATE ON reserva
FOR EACH ROW
BEGIN
    DECLARE v_id_espera  INT UNSIGNED DEFAULT NULL;
    DECLARE v_id_usuario INT UNSIGNED DEFAULT NULL;
    DECLARE v_posicao    SMALLINT UNSIGNED DEFAULT NULL;
    -- se a fila estiver vazia o SELECT ... INTO nao acha linha: apenas segue
    DECLARE CONTINUE HANDLER FOR NOT FOUND SET v_id_espera = NULL;

    IF NOT (OLD.status <=> NEW.status) THEN          -- <=> compara tratando NULL
        INSERT INTO log_auditoria (tabela, id_registro, acao, id_usuario, detalhes)
        VALUES ('reserva', NEW.id_reserva, 'STATUS', @id_usuario_app,
                JSON_OBJECT('de', OLD.status, 'para', NEW.status));
    END IF;

    IF NEW.status = 'CANCELADA' AND OLD.status <> 'CANCELADA' THEN
        SELECT le.id_espera, le.id_usuario, le.posicao
          INTO v_id_espera, v_id_usuario, v_posicao
          FROM lista_espera le
         WHERE le.id_quadra    = NEW.id_quadra
           AND le.data_reserva = NEW.data_reserva
           AND le.hora_inicio  = NEW.hora_inicio
           AND le.status       = 'AGUARDANDO'
         ORDER BY le.posicao
         LIMIT 1;

        IF v_id_espera IS NOT NULL THEN
            UPDATE lista_espera
               SET status = 'NOTIFICADO', notificado_em = NOW()
             WHERE id_espera = v_id_espera;

            INSERT INTO log_auditoria (tabela, id_registro, acao, id_usuario, detalhes)
            VALUES ('lista_espera', v_id_espera, 'NOTIFICAR_ESPERA', @id_usuario_app,
                    JSON_OBJECT('id_reserva_cancelada', NEW.id_reserva,
                                'notificar_usuario',    v_id_usuario,
                                'posicao',              v_posicao,
                                'mensagem',             'Horario liberado: avisar o cliente'));
        END IF;
    END IF;
END$$

-- -----------------------------------------------------------------------------
-- Exclusao fisica de reserva (rara - o normal e cancelar) tambem fica no log,
-- com uma copia dos dados principais, ja que a linha deixa de existir.
-- -----------------------------------------------------------------------------
CREATE TRIGGER trg_reserva_ad
AFTER DELETE ON reserva
FOR EACH ROW
BEGIN
    INSERT INTO log_auditoria (tabela, id_registro, acao, id_usuario, detalhes)
    VALUES ('reserva', OLD.id_reserva, 'DELETE', @id_usuario_app,
            JSON_OBJECT('id_usuario', OLD.id_usuario, 'id_quadra', OLD.id_quadra,
                        'data', OLD.data_reserva, 'hora', TIME_FORMAT(OLD.hora_inicio, '%H:%i'),
                        'status', OLD.status));
END$$

-- -----------------------------------------------------------------------------
-- So avalia quem jogou: a reserva precisa estar CONCLUIDA.
-- (Um CHECK nao pode consultar outra tabela, por isso e um trigger.)
-- -----------------------------------------------------------------------------
CREATE TRIGGER trg_avaliacao_bi
BEFORE INSERT ON avaliacao
FOR EACH ROW
BEGIN
    IF (SELECT status FROM reserva WHERE id_reserva = NEW.id_reserva) <> 'CONCLUIDA' THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Somente reservas CONCLUIDAS podem ser avaliadas.';
    END IF;
END$$

-- -----------------------------------------------------------------------------
-- Posicao automatica na fila: se a aplicacao nao informar a posicao (ou
-- informar 0), entra no fim da fila daquele horario.
-- -----------------------------------------------------------------------------
CREATE TRIGGER trg_lista_espera_bi
BEFORE INSERT ON lista_espera
FOR EACH ROW
BEGIN
    IF NEW.posicao IS NULL OR NEW.posicao = 0 THEN
        SET NEW.posicao = (SELECT COALESCE(MAX(le.posicao), 0) + 1
                             FROM lista_espera le
                            WHERE le.id_quadra    = NEW.id_quadra
                              AND le.data_reserva = NEW.data_reserva
                              AND le.hora_inicio  = NEW.hora_inicio);
    END IF;
END$$

DELIMITER ;


-- =============================================================================
-- STORED PROCEDURE sp_reservar
-- Faz no banco o mesmo que agenda_agendar() faz no C, com tudo dentro de UMA
-- transacao: ou a reserva e gravada inteira, ou nada e gravado.
--
--   CALL sp_reservar(id_usuario, id_quadra, data, hora, id_modalidade, @id);
--   SELECT @id;   -- codigo da reserva criada
--
-- Ajuste em relacao ao pedido (usuario, quadra, data, hora): foi incluido o
-- parametro p_id_modalidade, porque a reserva guarda o esporte (relatorios e
-- FK quadra_modalidade). Ele pode ser NULL quando a quadra so tem uma
-- modalidade (Society, Futsal) - a procedure descobre sozinha.
--
-- Ordem das validacoes (mensagens iguais as do src/servico/erros.c):
--   1. hora cheia             5. modalidade oferecida na quadra
--   2. usuario existe         6. horario nao pertence a um mensalista
--   3. quadra existe e ativa  7. conflito (RN01)
--   4. data/hora nao passou e esta no funcionamento da quadra (RN02/RN05)
--   8. preco existe -> INSERT com status PENDENTE (aguardando o sinal)
--
-- Concorrencia: o SELECT ... FOR UPDATE na quadra trava a linha da quadra ate
-- o COMMIT. Dois pedidos simultaneos para a MESMA quadra sao atendidos um de
-- cada vez (o segundo ja ve a reserva do primeiro). Mesmo que isso falhasse,
-- o UNIQUE uk_reserva_horario recusaria a duplicata (erro 1062), tratado
-- abaixo com a mesma mensagem de conflito.
-- =============================================================================
DELIMITER $$
CREATE PROCEDURE sp_reservar (
    IN  p_id_usuario    INT UNSIGNED,
    IN  p_id_quadra     SMALLINT UNSIGNED,
    IN  p_data          DATE,
    IN  p_hora          TIME,
    IN  p_id_modalidade SMALLINT UNSIGNED,
    OUT p_id_reserva    INT UNSIGNED
)
BEGIN
    DECLARE v_ativa      BOOLEAN DEFAULT NULL;
    DECLARE v_abertura   TIME DEFAULT NULL;
    DECLARE v_fechamento TIME DEFAULT NULL;
    DECLARE v_modalidade SMALLINT UNSIGNED DEFAULT p_id_modalidade;
    DECLARE v_qtd        INT DEFAULT 0;
    DECLARE v_valor      DECIMAL(8,2) DEFAULT NULL;

    -- Erro 1062 = chave UNIQUE duplicada -> a regra principal foi violada
    DECLARE EXIT HANDLER FOR 1062
    BEGIN
        ROLLBACK;
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Ja existe agendamento nesta quadra, dia e horario.';
    END;

    -- Qualquer outro erro (inclusive os SIGNAL abaixo): desfaz e repassa a
    -- mensagem original para quem chamou.
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    SET p_id_reserva = NULL;

    START TRANSACTION;

    -- 1. hora cheia, como no C (int hora)
    IF p_hora IS NULL OR MINUTE(p_hora) <> 0 OR SECOND(p_hora) <> 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Horario invalido: use hora cheia (ex.: 19:00).';
    END IF;

    -- 2. usuario
    IF NOT EXISTS (SELECT 1 FROM usuario WHERE id_usuario = p_id_usuario) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Usuario nao encontrado.';
    END IF;

    -- 3. quadra (RN03) - FOR UPDATE trava a quadra ate o fim da transacao
    SELECT ativa INTO v_ativa FROM quadra WHERE id_quadra = p_id_quadra FOR UPDATE;
    IF v_ativa IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Quadra nao encontrada.';
    ELSEIF NOT v_ativa THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Quadra desativada para reservas.';
    END IF;

    -- 4a. data (RN05): nao pode ser passado; se for hoje, a hora nao pode ter passado
    IF p_data IS NULL
       OR p_data < CURDATE()
       OR (p_data = CURDATE() AND HOUR(p_hora) <= HOUR(CURTIME())) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Data invalida ou no passado (use AAAA-MM-DD).';
    END IF;

    -- 4b. funcionamento da quadra naquele dia da semana (RN02)
    SELECT hora_abertura, hora_fechamento INTO v_abertura, v_fechamento
      FROM horario_funcionamento
     WHERE id_quadra = p_id_quadra AND dia_semana = DAYOFWEEK(p_data);

    IF v_abertura IS NULL
       OR p_hora < v_abertura
       OR ADDTIME(p_hora, '01:00:00') > v_fechamento THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Horario fora do funcionamento da quadra.';
    END IF;

    -- 5. modalidade
    IF v_modalidade IS NULL THEN
        SELECT COUNT(*), MIN(id_modalidade) INTO v_qtd, v_modalidade
          FROM quadra_modalidade WHERE id_quadra = p_id_quadra;
        IF v_qtd <> 1 THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'Informe a modalidade: esta quadra atende mais de um esporte.';
        END IF;
    ELSEIF NOT EXISTS (SELECT 1 FROM quadra_modalidade
                        WHERE id_quadra = p_id_quadra AND id_modalidade = v_modalidade) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Modalidade nao oferecida nesta quadra.';
    END IF;

    -- 6. horario fixo de outro cliente (mensalista ativo no periodo)
    IF EXISTS (SELECT 1 FROM mensalista ms
                WHERE ms.id_quadra   = p_id_quadra
                  AND ms.dia_semana  = DAYOFWEEK(p_data)
                  AND ms.hora_inicio = p_hora
                  AND ms.ativo
                  AND p_data >= ms.data_inicio
                  AND (ms.data_fim IS NULL OR p_data <= ms.data_fim)
                  AND ms.id_usuario <> p_id_usuario) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Horario reservado para um mensalista.';
    END IF;

    -- 7. conflito (RN01) - checagem amigavel; o UNIQUE e a garantia final
    IF EXISTS (SELECT 1 FROM reserva
                WHERE id_quadra    = p_id_quadra
                  AND data_reserva = p_data
                  AND hora_inicio  = p_hora
                  AND status      <> 'CANCELADA') THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Ja existe agendamento nesta quadra, dia e horario.';
    END IF;

    -- 8. preco dinamico
    SET v_valor = fn_valor_hora(p_id_quadra, p_data, p_hora);
    IF v_valor IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Nao ha preco cadastrado para este horario.';
    END IF;

    INSERT INTO reserva (id_usuario, id_quadra, id_modalidade, data_reserva,
                         hora_inicio, hora_fim, status, valor_total)
    VALUES (p_id_usuario, p_id_quadra, v_modalidade, p_data,
            p_hora, ADDTIME(p_hora, '01:00:00'), 'PENDENTE', v_valor);

    SET p_id_reserva = LAST_INSERT_ID();

    -- se o cliente estava na fila de espera deste horario, foi atendido
    UPDATE lista_espera
       SET status = 'ATENDIDO'
     WHERE id_usuario   = p_id_usuario
       AND id_quadra    = p_id_quadra
       AND data_reserva = p_data
       AND hora_inicio  = p_hora
       AND status IN ('AGUARDANDO', 'NOTIFICADO');

    COMMIT;
END$$
DELIMITER ;
