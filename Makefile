DOCKER ?= docker
COMPOSE = $(DOCKER) compose
MYSQL = $(COMPOSE) exec -T mysql mysql --protocol=TCP -h 127.0.0.1 -uroot -proot -D index_lab

.PHONY: up down reset bad-index test shell

up:
	$(COMPOSE) up -d --wait

down:
	$(COMPOSE) down -v

reset: down up
	$(MYSQL) < sql/01_schema.sql
	$(MYSQL) < sql/02_seed.sql

bad-index: up
	$(MYSQL) < sql/03_add_bad_index.sql

test: up
	DOCKER='$(DOCKER)' bash tests/assert_composite_index_plan.sh

shell: up
	$(MYSQL)
