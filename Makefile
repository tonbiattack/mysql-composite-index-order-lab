DOCKER ?= docker
COMPOSE = $(DOCKER) compose
MYSQL = $(COMPOSE) exec -T mysql mysql --protocol=TCP -h 127.0.0.1 -uroot -proot -D index_lab

.PHONY: up down reset bad-index good-index observe-bad observe-good test shell

up:
	$(COMPOSE) up -d --wait

down:
	$(COMPOSE) down -v

reset: down up
	$(MYSQL) < sql/01_schema.sql
	$(MYSQL) < sql/02_seed.sql

bad-index: up
	$(MYSQL) < sql/03_add_bad_index.sql

good-index: up
	$(MYSQL) < sql/04_replace_with_good_index.sql

observe-bad: up
	$(MYSQL) < sql/20_observe_bad_index.sql > evidence/bad_index_plan.txt

observe-good: up
	$(MYSQL) < sql/21_observe_good_index.sql > evidence/good_index_plan.txt

test: up
	DOCKER='$(DOCKER)' bash tests/assert_composite_index_plan.sh

shell: up
	$(MYSQL)
