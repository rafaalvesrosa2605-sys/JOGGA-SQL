-- =============================================================
-- JOGGA - Banco de dados do sistema de agendamento de quadras
-- PIM II - Analise e Desenvolvimento de Sistemas - UNIP
-- SGBD: MySQL 8
--
-- Como usar: cole tudo no MySQL Workbench e execute (Ctrl+Shift+Enter).
-- =============================================================

DROP DATABASE IF EXISTS jogga;
CREATE DATABASE jogga CHARACTER SET utf8mb4;
USE jogga;


-- =============================================================
-- 1. CRIACAO DAS TABELAS
-- =============================================================

-- Pessoas que usam o sistema (cliente, recepcao ou administrador).
-- A senha e guardada como hash, nunca em texto puro.
CREATE TABLE usuario (
    id_usuario  INT AUTO_INCREMENT PRIMARY KEY,
    nome        VARCHAR(100) NOT NULL,
    cpf         CHAR(11)     NOT NULL UNIQUE,
    email       VARCHAR(120) NOT NULL UNIQUE,
    telefone    VARCHAR(15)  NOT NULL,
    senha_hash  VARCHAR(255) NOT NULL,
    perfil      ENUM('CLIENTE', 'RECEPCAO', 'ADMIN') NOT NULL DEFAULT 'CLIENTE',
    criado_em   DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Esportes oferecidos pela arena.
CREATE TABLE modalidade (
    id_modalidade INT AUTO_INCREMENT PRIMARY KEY,
    nome          VARCHAR(40) NOT NULL UNIQUE
);

-- Quadras da arena e o preco da hora.
CREATE TABLE quadra (
    id_quadra  INT AUTO_INCREMENT PRIMARY KEY,
    nome       VARCHAR(40)  NOT NULL UNIQUE,
    tipo_piso  VARCHAR(30)  NOT NULL,
    coberta    BOOLEAN      NOT NULL DEFAULT FALSE,
    valor_hora DECIMAL(8,2) NOT NULL CHECK (valor_hora > 0),
    ativa      BOOLEAN      NOT NULL DEFAULT TRUE
);

-- Uma quadra pode ter varios esportes e um esporte pode estar em
-- varias quadras (relacionamento N:N). Esta tabela liga as duas.
CREATE TABLE quadra_modalidade (
    id_quadra     INT NOT NULL,
    id_modalidade INT NOT NULL,
    PRIMARY KEY (id_quadra, id_modalidade),
    FOREIGN KEY (id_quadra)     REFERENCES quadra (id_quadra),
    FOREIGN KEY (id_modalidade) REFERENCES modalidade (id_modalidade)
);

-- Reservas: uma quadra, um dia, uma hora (cada reserva dura 1 hora).
CREATE TABLE reserva (
    id_reserva    INT AUTO_INCREMENT PRIMARY KEY,
    id_usuario    INT  NOT NULL,
    id_quadra     INT  NOT NULL,
    id_modalidade INT  NOT NULL,
    data_reserva  DATE NOT NULL,
    hora_inicio   TIME NOT NULL,
    status        ENUM('CONFIRMADA', 'CANCELADA', 'CONCLUIDA', 'NO_SHOW')
                  NOT NULL DEFAULT 'CONFIRMADA',
    valor         DECIMAL(8,2) NOT NULL CHECK (valor > 0),
    criado_em     DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,

    -- Regra principal: nunca duas reservas na mesma quadra, dia e hora.
    -- Problema: uma reserva CANCELADA nao pode continuar ocupando o horario.
    -- Solucao: esta coluna e calculada pelo proprio banco. Ela fica NULL
    -- quando a reserva e cancelada, e o UNIQUE ignora valores NULL.
    hora_ocupada  TIME GENERATED ALWAYS AS
                  (CASE WHEN status = 'CANCELADA' THEN NULL ELSE hora_inicio END) STORED,
    CONSTRAINT uk_horario UNIQUE (id_quadra, data_reserva, hora_ocupada),

    -- funcionamento das 08h as 23h: o ultimo horario comeca as 22h
    CONSTRAINT ck_horario CHECK (hora_inicio BETWEEN '08:00:00' AND '22:00:00'),

    FOREIGN KEY (id_usuario)    REFERENCES usuario (id_usuario),
    FOREIGN KEY (id_quadra)     REFERENCES quadra (id_quadra),
    FOREIGN KEY (id_modalidade) REFERENCES modalidade (id_modalidade)
);

-- Pagamentos de cada reserva (ex.: sinal no Pix + restante no balcao).
CREATE TABLE pagamento (
    id_pagamento INT AUTO_INCREMENT PRIMARY KEY,
    id_reserva   INT NOT NULL,
    forma        ENUM('PIX', 'CARTAO', 'DINHEIRO') NOT NULL,
    valor        DECIMAL(8,2) NOT NULL CHECK (valor > 0),
    pago_em      DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (id_reserva) REFERENCES reserva (id_reserva)
);

-- Nota de 1 a 5 dada depois do jogo (no maximo uma por reserva).
CREATE TABLE avaliacao (
    id_avaliacao INT AUTO_INCREMENT PRIMARY KEY,
    id_reserva   INT NOT NULL UNIQUE,
    nota         INT NOT NULL CONSTRAINT ck_nota CHECK (nota BETWEEN 1 AND 5),
    comentario   VARCHAR(300),
    FOREIGN KEY (id_reserva) REFERENCES reserva (id_reserva)
);

-- Indices para as buscas mais comuns (agenda do dia e reservas do cliente).
CREATE INDEX idx_reserva_data    ON reserva (data_reserva);
CREATE INDEX idx_reserva_usuario ON reserva (id_usuario);


-- =============================================================
-- 2. DADOS DE EXEMPLO
-- =============================================================

-- Senhas: hashes ficticios (nenhuma senha real).
INSERT INTO usuario (nome, cpf, email, telefone, senha_hash, perfil) VALUES
('Mariana Costa',    '10433218100', 'mariana@exemplo.com',  '11987650001', '$2b$10$hashFicticioAdmin000001', 'ADMIN'),
('Paulo Dias',       '83276483572', 'paulo@exemplo.com',    '11987650002', '$2b$10$hashFicticioRecep00002', 'RECEPCAO'),
('Lucas Ferreira',   '70106513370', 'lucas@exemplo.com',    '11976540003', '$2b$10$hashFicticioClien00003', 'CLIENTE'),
('Bruno Almeida',    '69985435303', 'bruno@exemplo.com',    '11976540004', '$2b$10$hashFicticioClien00004', 'CLIENTE'),
('Camila Rodrigues', '28059826220', 'camila@exemplo.com',   '11976540005', '$2b$10$hashFicticioClien00005', 'CLIENTE'),
('Diego Martins',    '69816934027', 'diego@exemplo.com',    '11976540006', '$2b$10$hashFicticioClien00006', 'CLIENTE'),
('Fernanda Lima',    '63201632830', 'fernanda@exemplo.com', '11976540007', '$2b$10$hashFicticioClien00007', 'CLIENTE'),
('Gabriel Souza',    '73467065600', 'gabriel@exemplo.com',  '11976540008', '$2b$10$hashFicticioClien00008', 'CLIENTE'),
('Thiago Oliveira',  '31931491950', 'thiago@exemplo.com',   '11976540009', '$2b$10$hashFicticioClien00009', 'CLIENTE'),
('Patricia Gomes',   '43634957824', 'patricia@exemplo.com', '11976540010', '$2b$10$hashFicticioClien00010', 'CLIENTE');

INSERT INTO modalidade (nome) VALUES
('Futebol society'), ('Futsal'), ('Volei'), ('Basquete'), ('Beach tennis'), ('Futevolei');

INSERT INTO quadra (nome, tipo_piso, coberta, valor_hora) VALUES
('Society 1',     'grama sintetica', FALSE, 180.00),
('Society 2',     'grama sintetica', FALSE, 180.00),
('Futsal',        'madeira',         TRUE,  150.00),
('Poliesportiva', 'poliuretano',     TRUE,  120.00),
('Areia',         'areia',           FALSE, 100.00);

-- Quais esportes cada quadra recebe
INSERT INTO quadra_modalidade (id_quadra, id_modalidade) VALUES
(1, 1), (2, 1),          -- society
(3, 2),                  -- futsal
(4, 3), (4, 4),          -- poliesportiva: volei e basquete
(5, 5), (5, 6);          -- areia: beach tennis e futevolei

-- Reservas de outubro de 2026 (ate dia 15 ja aconteceram; depois, futuras)
INSERT INTO reserva (id_usuario, id_quadra, id_modalidade, data_reserva, hora_inicio, status, valor) VALUES
( 3, 1, 1, '2026-10-01', '19:00', 'CONCLUIDA',  180.00),   -- 1
( 4, 1, 1, '2026-10-01', '20:00', 'CONCLUIDA',  180.00),   -- 2
( 5, 3, 2, '2026-10-02', '18:00', 'CONCLUIDA',  150.00),   -- 3
( 6, 5, 5, '2026-10-03', '09:00', 'CONCLUIDA',  100.00),   -- 4
( 7, 4, 3, '2026-10-05', '19:00', 'CONCLUIDA',  120.00),   -- 5
( 8, 2, 1, '2026-10-06', '21:00', 'NO_SHOW',    180.00),   -- 6  Gabriel faltou
( 3, 1, 1, '2026-10-08', '19:00', 'CONCLUIDA',  180.00),   -- 7
( 9, 3, 2, '2026-10-09', '20:00', 'CONCLUIDA',  150.00),   -- 8
( 8, 1, 1, '2026-10-10', '22:00', 'NO_SHOW',    180.00),   -- 9  Gabriel faltou de novo
(10, 4, 4, '2026-10-12', '18:00', 'CANCELADA',  120.00),   -- 10
( 4, 2, 1, '2026-10-13', '20:00', 'CONCLUIDA',  180.00),   -- 11
( 6, 5, 6, '2026-10-14', '17:00', 'CONCLUIDA',  100.00),   -- 12
( 3, 1, 1, '2026-10-15', '19:00', 'CONCLUIDA',  180.00),   -- 13
( 5, 3, 2, '2026-10-16', '19:00', 'CONFIRMADA', 150.00),   -- 14
( 7, 4, 3, '2026-10-17', '19:00', 'CONFIRMADA', 120.00),   -- 15
( 9, 1, 1, '2026-10-20', '20:00', 'CONFIRMADA', 180.00),   -- 16
(10, 5, 5, '2026-10-22', '10:00', 'CONFIRMADA', 100.00),   -- 17
( 3, 1, 1, '2026-10-22', '19:00', 'CONFIRMADA', 180.00),   -- 18
( 8, 2, 1, '2026-10-24', '21:00', 'CANCELADA',  180.00),   -- 19
( 4, 3, 2, '2026-10-29', '20:00', 'CONFIRMADA', 150.00);   -- 20

-- Jogos concluidos: pagos por inteiro (a reserva 2 pagou sinal no Pix e o
-- restante no cartao). No-show e confirmadas: sinal de 50% no Pix.
INSERT INTO pagamento (id_reserva, forma, valor, pago_em) VALUES
( 1, 'PIX',      180.00, '2026-10-01 18:30'),
( 2, 'PIX',       90.00, '2026-09-29 10:00'),
( 2, 'CARTAO',    90.00, '2026-10-01 19:50'),
( 3, 'DINHEIRO', 150.00, '2026-10-02 17:55'),
( 4, 'PIX',      100.00, '2026-10-03 08:40'),
( 5, 'CARTAO',   120.00, '2026-10-05 18:50'),
( 6, 'PIX',       90.00, '2026-10-04 10:00'),
( 7, 'PIX',      180.00, '2026-10-08 18:45'),
( 8, 'DINHEIRO', 150.00, '2026-10-09 19:55'),
( 9, 'PIX',       90.00, '2026-10-08 12:00'),
(11, 'CARTAO',   180.00, '2026-10-13 19:50'),
(12, 'PIX',      100.00, '2026-10-14 16:40'),
(13, 'PIX',      180.00, '2026-10-15 18:30'),
(14, 'PIX',       75.00, '2026-10-12 09:00'),
(15, 'PIX',       60.00, '2026-10-12 10:00'),
(16, 'PIX',       90.00, '2026-10-12 11:00'),
(17, 'PIX',       50.00, '2026-10-12 12:00'),
(18, 'PIX',       90.00, '2026-10-12 13:00'),
(20, 'PIX',       75.00, '2026-10-12 14:00');

INSERT INTO avaliacao (id_reserva, nota, comentario) VALUES
( 1, 5, 'Grama nova e boa iluminacao.'),
( 2, 4, 'Muito boa.'),
( 3, 4, 'Piso excelente.'),
( 4, 5, 'Areia bem cuidada.'),
( 5, 3, 'Rede do volei estava frouxa.'),
( 7, 5, NULL),
( 8, 2, 'Vestiario sujo.'),
(11, 3, 'Gramado gasto perto do gol.'),
(12, 4, NULL),
(13, 5, 'Sempre impecavel.');


-- =============================================================
-- 3. VIEW (consulta salva)
-- =============================================================

-- Agenda com os nomes, para a recepcao (sem as canceladas).
CREATE VIEW vw_agenda AS
SELECT r.id_reserva, r.data_reserva, r.hora_inicio,
       q.nome AS quadra, m.nome AS modalidade,
       u.nome AS cliente, u.telefone, r.status, r.valor
  FROM reserva r
  JOIN quadra     q ON q.id_quadra     = r.id_quadra
  JOIN modalidade m ON m.id_modalidade = r.id_modalidade
  JOIN usuario    u ON u.id_usuario    = r.id_usuario
 WHERE r.status <> 'CANCELADA';


-- =============================================================
-- 4. CONSULTAS
-- =============================================================

-- 4.1 Agenda de um dia
SELECT hora_inicio, quadra, modalidade, cliente, telefone, status
  FROM vw_agenda
 WHERE data_reserva = '2026-10-22'
 ORDER BY hora_inicio;

-- 4.2 Horarios ocupados de uma quadra em uma data
SELECT hora_inicio
  FROM reserva
 WHERE id_quadra = 1
   AND data_reserva = '2026-10-22'
   AND status <> 'CANCELADA'
 ORDER BY hora_inicio;

-- 4.3 Reservas de um cliente (Lucas)
SELECT data_reserva, hora_inicio, quadra, status, valor
  FROM vw_agenda
 WHERE cliente = 'Lucas Ferreira'
 ORDER BY data_reserva;

-- 4.4 Faturamento por quadra (soma dos pagamentos)
SELECT q.nome AS quadra, SUM(p.valor) AS faturamento
  FROM pagamento p
  JOIN reserva r ON r.id_reserva = p.id_reserva
  JOIN quadra  q ON q.id_quadra  = r.id_quadra
 GROUP BY q.nome
 ORDER BY faturamento DESC;

-- 4.5 Horarios mais procurados
SELECT hora_inicio, COUNT(*) AS reservas
  FROM reserva
 WHERE status <> 'CANCELADA'
 GROUP BY hora_inicio
 ORDER BY reservas DESC;

-- 4.6 Clientes que mais faltaram sem avisar (no-show)
SELECT u.nome, COUNT(*) AS faltas
  FROM reserva r
  JOIN usuario u ON u.id_usuario = r.id_usuario
 WHERE r.status = 'NO_SHOW'
 GROUP BY u.nome
 ORDER BY faltas DESC;

-- 4.7 Nota media de cada quadra
SELECT q.nome AS quadra, ROUND(AVG(a.nota), 1) AS nota_media, COUNT(*) AS avaliacoes
  FROM avaliacao a
  JOIN reserva r ON r.id_reserva = a.id_reserva
  JOIN quadra  q ON q.id_quadra  = r.id_quadra
 GROUP BY q.nome
 ORDER BY nota_media DESC;

-- 4.8 Quanto falta receber das reservas confirmadas
SELECT r.id_reserva, u.nome AS cliente, r.data_reserva, r.valor,
       COALESCE(SUM(p.valor), 0)           AS pago,
       r.valor - COALESCE(SUM(p.valor), 0) AS falta_pagar
  FROM reserva r
  JOIN usuario u ON u.id_usuario = r.id_usuario
  LEFT JOIN pagamento p ON p.id_reserva = r.id_reserva
 WHERE r.status = 'CONFIRMADA'
 GROUP BY r.id_reserva, u.nome, r.data_reserva, r.valor
 ORDER BY r.data_reserva;


-- =============================================================
-- 5. EXEMPLOS DE INSERT, UPDATE E DELETE
-- =============================================================

-- INSERT: novo cliente
INSERT INTO usuario (nome, cpf, email, telefone, senha_hash)
VALUES ('Renata Teixeira', '52998224725', 'renata@exemplo.com', '11976540011', '$2b$10$hashFicticioClien00011');

-- INSERT: reserva para ela (Areia, beach tennis)
INSERT INTO reserva (id_usuario, id_quadra, id_modalidade, data_reserva, hora_inicio, valor)
VALUES (11, 5, 5, '2026-10-30', '09:00', 100.00);

-- UPDATE: o jogo de 16/10 aconteceu
UPDATE reserva SET status = 'CONCLUIDA' WHERE id_reserva = 14;

-- UPDATE: reajuste de 10% nas quadras society
UPDATE quadra SET valor_hora = valor_hora * 1.10 WHERE nome LIKE 'Society%';

-- DELETE: apagar uma reserva cancelada que nao tem pagamento
DELETE FROM reserva WHERE id_reserva = 19;

-- Conferindo
SELECT * FROM vw_agenda ORDER BY data_reserva, hora_inicio;
