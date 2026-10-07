.PHONY: help up-local down-local down-local-clean status-local logs-local \
        shell-primary shell-haproxy \
        up-primary-prod up-replica1-prod up-replica2-prod up-haproxy-prod \
        down-primary-prod down-replica1-prod down-replica2-prod down-haproxy-prod \
        test-write test-read test-failover

help:
	@echo "LOCAL:"
	@echo "  make up-local          Start all containers locally"
	@echo "  make down-local        Stop"
	@echo "  make down-local-clean  Stop + remove volumes"
	@echo "  make status-local      Show status"
	@echo "  make logs-local        HAProxy logs"
	@echo ""
	@echo "PROD (run on correct VM):"
	@echo "  make up-primary-prod   VM1"
	@echo "  make up-haproxy-prod   VM1"
	@echo "  make up-replica1-prod  VM2"
	@echo "  make up-replica2-prod  VM3"
	@echo ""
	@echo "TESTS (from laptop, local only):"
	@echo "  make test-write        INSERT via :5000"
	@echo "  make test-read         Round-robin SELECT via :5001"
	@echo "  make test-failover     Stop replica1, verify failover"

# ============================================================
# LOCAL
# ============================================================
up-local:
	cd docker-compose/local && docker compose --env-file ../../.env up -d
	@sleep 8
	@docker ps --filter "name=postgres-" --filter "name=haproxy" \
	  --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

down-local:
	cd docker-compose/local && docker compose --env-file ../../.env down

down-local-clean:
	cd docker-compose/local && docker compose --env-file ../../.env down -v

status-local:
	@docker ps --filter "name=postgres-" --filter "name=haproxy" \
	  --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
	@echo ""
	@docker exec postgres-primary psql -U postgres -c \
	  "SELECT client_addr, state, sync_state FROM pg_stat_replication;" || true

logs-local:
	docker logs -f haproxy

shell-primary:
	docker exec -it postgres-primary psql -U postgres -d mydb

shell-haproxy:
	docker exec -it haproxy sh

# ============================================================
# PROD (run per VM)
# ============================================================
up-primary-prod:
	cd docker-compose/primary && docker compose --env-file ../../.env up -d

down-primary-prod:
	cd docker-compose/primary && docker compose --env-file ../../.env down

up-replica1-prod:
	cd docker-compose/replica1 && docker compose --env-file ../../.env up -d

down-replica1-prod:
	cd docker-compose/replica1 && docker compose --env-file ../../.env down

up-replica2-prod:
	cd docker-compose/replica2 && docker compose --env-file ../../.env up -d

down-replica2-prod:
	cd docker-compose/replica2 && docker compose --env-file ../../.env down

up-haproxy-prod:
	cd docker-compose/haproxy && docker compose --env-file ../../.env up -d

down-haproxy-prod:
	cd docker-compose/haproxy && docker compose --env-file ../../.env down

# ============================================================
# TESTS (local)
# ============================================================
test-write:
	@PGPASSWORD=$${POSTGRES_PASSWORD:-postgres} psql -h localhost -p 5000 \
	  -U $${POSTGRES_USER:-postgres} -d $${POSTGRES_DB:-mydb} \
	  -c "INSERT INTO test_replication (data) VALUES ('test at $$(date)');"

test-read:
	@for i in 1 2 3 4; do \
	  echo -n "Request $$i → "; \
	  PGPASSWORD=$${POSTGRES_PASSWORD:-postgres} psql -h localhost -p 5001 \
	    -U $${POSTGRES_USER:-postgres} -d $${POSTGRES_DB:-mydb} \
	    -t -A -c "SELECT inet_server_addr() || ' | is_replica=' || pg_is_in_recovery();"; \
	done

test-failover:
	@echo "Stopping replica1..."
	docker stop postgres-replica1
	@sleep 6
	@for i in 1 2 3; do \
	  echo -n "Request $$i → "; \
	  PGPASSWORD=$${POSTGRES_PASSWORD:-postgres} psql -h localhost -p 5001 \
	    -U $${POSTGRES_USER:-postgres} -d $${POSTGRES_DB:-mydb} \
	    -t -A -c "SELECT inet_server_addr();"; \
	done
	@echo "Restarting replica1..."
	docker start postgres-replica1
