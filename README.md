# JOGGA-SQL - Banco de dados do sistema de agendamento de quadras

Banco de dados do **JOGGA**, sistema de agendamento de quadras da Arena Meio-Campo Esportes (organização fictícia com 5 quadras). Projeto em grupo do **PIM II** do curso de Análise e Desenvolvimento de Sistemas da **UNIP**, Etapa 4: Modelagem de Banco de Dados e NoSQL.

- **SGBD:** MySQL 8
- **7 tabelas:** usuario, modalidade, quadra, quadra_modalidade, reserva, pagamento e avaliacao
- **Regra principal:** nunca existem duas reservas na mesma quadra, no mesmo dia e horário. Quem garante isso é o próprio banco, e uma reserva cancelada libera o horário.
- **Funcionamento:** das 08h às 23h, com reservas de 1 hora (o último horário começa às 22h)

![DER](docs/der_conceitual.png)

## Arquivos

| Arquivo | O que tem |
|---|---|
| [`banco/jogga.sql`](banco/jogga.sql) | criação das tabelas, dados de exemplo, view, 8 consultas e exemplos de INSERT, UPDATE e DELETE |
| [`banco/jogga_testes.sql`](banco/jogga_testes.sql) | testes das regras: 4 comandos que devem dar erro e 1 que deve funcionar |
| [`docs/banco_de_dados.md`](docs/banco_de_dados.md) | modelo conceitual, DER, modelo lógico, normalização (1FN a 3FN), dicionário de dados e NoSQL |

## Como executar (MySQL Workbench)

1. Abra o `banco/jogga.sql` (*File > Open SQL Script*), ou copie e cole o conteúdo dele em uma aba de query.
2. Execute tudo com o raio ⚡ (`Ctrl+Shift+Enter`).
3. Para os testes, abra o `banco/jogga_testes.sql` e execute **um comando por vez** (cursor na linha + `Ctrl+Enter`). Os 4 primeiros dão erro de propósito: é o banco recusando dados inválidos.

Pela linha de comando:

```
mysql -u root -p < banco/jogga.sql
mysql -u root -p --force < banco/jogga_testes.sql
```

O script apaga e recria o banco `jogga`. Para voltar aos dados iniciais, basta rodar o `jogga.sql` de novo.

---

PIM II - Análise e Desenvolvimento de Sistemas - UNIP
