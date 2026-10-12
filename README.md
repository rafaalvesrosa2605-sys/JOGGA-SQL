# JOGGA-SQL - Banco de dados do sistema de agendamento de quadras

Banco de dados relacional do **JOGGA**, sistema de agendamento de quadras da Arena Meio-Campo Esportes (organização fictícia com 5 quadras). Projeto em grupo do **PIM II** do curso de Análise e Desenvolvimento de Sistemas da **UNIP**, Etapa 4: Modelagem de Banco de Dados e NoSQL.

- **SGBD:** MySQL 8 (testado no 8.4 LTS), InnoDB, utf8mb4
- **Perfis:** cliente, recepção e administrador
- **Regra principal:** nunca existem duas reservas na mesma quadra, no mesmo dia e horário. O próprio banco garante isso com um `UNIQUE` sobre uma coluna gerada, que ignora reservas canceladas: o horário de uma reserva cancelada pode ser reservado de novo.
- **Funcionamento:** das 08h às 23h, reservas de 1 hora (último início às 22h)

![DER](docs/der.png)

## Conteúdo

| Arquivo | O que faz |
|---|---|
| [`banco/01_criacao.sql`](banco/01_criacao.sql) | apaga e recria o banco `jogga` com 13 tabelas, chaves, `CHECK` e índices |
| [`banco/02_dados_exemplo.sql`](banco/02_dados_exemplo.sql) | dados de exemplo: 15 usuários, 5 quadras, 42 reservas etc. (datas relativas ao dia de hoje) |
| [`banco/03_views_triggers_procedures.sql`](banco/03_views_triggers_procedures.sql) | 3 views, 6 triggers, função `fn_valor_hora` e procedure `sp_reservar` |
| [`banco/04_consultas.sql`](banco/04_consultas.sql) | 14 consultas comentadas e exemplos de INSERT, UPDATE e DELETE |
| [`banco/05_testes.sql`](banco/05_testes.sql) | testes: comandos que devem falhar e comandos que devem passar |
| [`docs/banco_de_dados.md`](docs/banco_de_dados.md) | modelo conceitual, DER, modelo lógico, normalização (1FN a 3FN), dicionário de dados e NoSQL (Redis e MongoDB) |

## Como executar

Rode os scripts **na ordem**. O script 01 **apaga** o banco `jogga` se ele existir; para refazer os testes do zero, rode de novo 01, 02 e 03.

**MySQL Workbench**

1. Conecte no servidor e abra cada script em *File > Open SQL Script*, na ordem da tabela acima.
2. Execute o script inteiro com o raio (*Execute*, `Ctrl+Shift+Enter`).
3. No `05_testes.sql` os erros são esperados: desmarque *Query > Stop Script Execution on Errors* antes de executar (ou rode teste por teste com `Ctrl+Enter`).

**Linha de comando** (dentro da pasta `banco/`)

```
mysql -u root -p < 01_criacao.sql
mysql -u root -p < 02_dados_exemplo.sql
mysql -u root -p < 03_views_triggers_procedures.sql
mysql -u root -p -t < 04_consultas.sql
mysql -u root -p -t --force < 05_testes.sql
```

`--force` faz o cliente continuar depois dos erros esperados do script 05.

## PostgreSQL

Os comentários marcados com `[PG]` nos scripts indicam o que trocar para rodar no PostgreSQL. A tabela de equivalências está no final de [`docs/banco_de_dados.md`](docs/banco_de_dados.md).

---

PIM II - Análise e Desenvolvimento de Sistemas - UNIP
