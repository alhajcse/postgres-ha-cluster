# ============================================================
# PostgreSQL HA Cluster — 5 VM
# ============================================================
# Roles: primary | replica1 | replica2 | haproxy | monitoring
#
# প্রতিটি VM-এ চালানোর আগে:
#   export HOST_ROLE=primary        (VM1)
#   export HOST_ROLE=replica1       (VM2)
#   export HOST_ROLE=replica2       (VM3)
#   export HOST_ROLE=haproxy        (VM4)
#   export HOST_ROLE=monitoring     (VM5)
#
# অথবা সরাসরি:
#   make up HOST_ROLE=primary
# ============================================================

SHELL := /bin/bash

# ---- Config ----
ENV_FILE := .env
HOST_ROLE ?=

# ---- VM IPs (default — override via .env) ----
VM1_IP := 10.70.16.231
VM2_IP := 10.70.16.232
VM3_IP := 10.70.16.233
VM4_IP := 10.70.16.234
VM5_IP := 10.70.16.235

# ---- Ports ----
WRITE_PORT  := 5000
READ_PORT   := 5001
STATS_PORT  := 7000
PROM_PORT   := 9090
GRAFANA_PORT:= 3000

# ---- Credentials (from .env at runtime) ----
PGUSER     := postgres
PGDATABASE := mydb

# ============================================================
# PHONY
# ============================================================
.PHONY: help \
        up down restart ps logs shell clean \
        up-primary down-primary logs-primary status-primary \
        up-replica1 down-replica1 logs-replica1 status-replica1 \
        up-replica2 down-replica2 logs-replica2 status-replica2 \
        up-haproxy down-haproxy logs-haproxy status-haproxy \
        up-monitoring down-monitoring logs-monitoring status-monitoring \
        up-all down-all \
        test-write test-read test-balance test-failover test-replication \
        test-monitoring test-ha-stats \
        check-firewall clean-all

# ============================================================
# HELP
# ============================================================
help:
	@echo "===================================================="
	@echo "  PostgreSQL HA Cluster (5 VM) — Makefile"
	@echo "===================================================="
	@echo ""
	@echo "  ROLE-SPECIFIC (run on correct VM):"
	@echo "    make up-primary          VM1 (10.70.16.231)"
	@echo "    make up-replica1         VM2 (10.70.16.232)"
	@echo "    make up-replica2         VM3 (10.70.16.233)"
	@echo "    make up-haproxy          VM4 (10.70.16.234)"
	@echo "    make up-monitoring       VM5 (10.70.16.235)"
	@echo ""
	@echo "  GENERIC (uses HOST_ROLE env):"
	@echo "    make up                  Start current role's stack"
	@echo "    make down                Stop current role's stack"
	@echo "    make restart             Restart current role's stack"
	@echo "    make ps                  Container status"
	@echo "    make logs                Follow logs"
	@echo "    make shell               Shell into main container"
	@echo ""
	@echo "  STATUS:"
	@echo "    make status-primary      Show replication on primary"
	@echo "    make status-haproxy      HAProxy backend status"
	@echo "    make status-monitoring   Prometheus targets"
	@echo ""
	@echo "  TESTS (from VM4 or any host with psql):"
	@echo "    make test-write          INSERT via HAProxy :5000"
	@echo "    make test-read           Round-robin read :5001"
	@echo "    make test-balance        Verify replica balance"
	@echo "    make test-failover       Stop replica1, verify failover"
	@echo "    make test-replication    Verify WAL streaming"
	@echo "    make test-monitoring     Check Prometheus scrape"
	@echo ""
	@echo "  UTILITIES:"
	@echo "    make check-firewall      Show required firewall ports"
	@echo "    make clean               Stop + remove volumes"
	@echo "    make clean-all           Stop + volumes + system prune"
	@echo ""

# ============================================================
# GENERIC DISPATCHER
# ============================================================
up:
	@if [ -z "$(HOST_ROLE)" ]; then \
	  echo "ERROR: HOST_ROLE not set."; \
	  echo "Usage: make up HOST_ROLE=primary|replica1|replica2|haproxy|monitoring"; \
	  exit 1; \
	fi
	@$(MAKE) --no-print-directory up-$(HOST_ROLE)

down:
	@if [ -z "$(HOST_ROLE)" ]; then \
	  echo "ERROR: HOST_ROLE not set."; exit 1; \
	fi
	@$(MAKE) --no-print-directory down-$(HOST_ROLE)

restart:
	@if [ -z "$(HOST_ROLE)" ]; then \
	  echo "ERROR: HOST_ROLE not set."; exit 1; \
	fi
	cd docker-compose/$(HOST_ROLE) && docker compose --env-file ../../$(ENV_FILE) restart

ps:
	@docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | \
	  grep -E "postgres|replica|haproxy|prometheus|grafana|alertmanager|exporter|NAMES"

logs:
	@if [ -z "$(HOST_ROLE)" ]; then \
	  echo "ERROR: HOST_ROLE not set."; exit 1; \
	fi
	@$(MAKE) --no-print-directory logs-$(HOST_ROLE)

shell:
	@case "$(HOST_ROLE)" in \
	  primary)  docker exec -it postgres-primary psql -U $(PGUSER) -d $(PGDATABASE) ;; \
	  replica1) docker exec -it postgres-replica1 psql -U $(PGUSER) -d $(PGDATABASE) ;; \
	  replica2) docker exec -it postgres-replica2 psql -U $(PGUSER) -d $(PGDATABASE) ;; \
	  haproxy)  docker exec -it haproxy sh ;; \
	  monitoring) docker exec -it prometheus sh ;; \
	  *) echo "Set HOST_ROLE first"; exit 1 ;; \
	esac

# ============================================================
# VM1 — PRIMARY (10.70.16.231)
# ============================================================
up-primary:
	cd docker-compose/primary && docker compose --env-file ../../$(ENV_FILE) up -d
	@sleep 8
	@$(MAKE) --no-print-directory ps-primary

down-primary:
	cd docker-compose/primary && docker compose --env-file ../../$(ENV_FILE) down

ps-primary:
	@docker ps --filter "name=postgres-primary" --filter "name=postgres-exporter" \
	           --filter "name=node-exporter" \
	           --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

logs-primary:
	docker logs -f postgres-primary

status-primary:
	@echo "=== Primary: replication status ==="
	@docker exec postgres-primary psql -U $(PGUSER) -c \
	  "SELECT client_addr, state, sync_state, replay_lag FROM pg_stat_replication;" || true
	@echo ""
	@echo "=== Replication slots ==="
	@docker exec postgres-primary psql -U $(PGUSER) -c \
	  "SELECT slot_name, active, restart_lsn FROM pg_replication_slots;" || true
	@echo ""
	@echo "=== Database size ==="
	@docker exec postgres-primary psql -U $(PGUSER) -c \
	  "SELECT pg_size_pretty(pg_database_size('$(PGDATABASE)'));" || true

# ============================================================
# VM2 — REPLICA1 (10.70.16.232)
# ============================================================
up-replica1:
	cd docker-compose/replica1 && docker compose --env-file ../../$(ENV_FILE) up -d
	@sleep 5
	@$(MAKE) --no-print-directory ps-replica1

down-replica1:
	cd docker-compose/replica1 && docker compose --env-file ../../$(ENV_FILE) down

ps-replica1:
	@docker ps --filter "name=postgres-replica1" --filter "name=postgres-exporter" \
	           --filter "name=node-exporter" \
	           --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

logs-replica1:
	docker logs -f postgres-replica1

status-replica1:
	@echo "=== Replica1 status ==="
	@docker exec postgres-replica1 psql -U $(PGUSER) -c \
	  "SELECT pg_is_in_recovery() AS is_replica, \
	          pg_last_wal_receive_lsn() AS received, \
	          pg_last_wal_replay_lsn() AS replayed, \
	          now() - pg_last_xact_replay_timestamp() AS lag;" || true

# ============================================================
# VM3 — REPLICA2 (10.70.16.233)
# ============================================================
up-replica2:
	cd docker-compose/replica2 && docker compose --env-file ../../$(ENV_FILE) up -d
	@sleep 5
	@$(MAKE) --no-print-directory ps-replica2

down-replica2:
	cd docker-compose/replica2 && docker compose --env-file ../../$(ENV_FILE) down

ps-replica2:
	@docker ps --filter "name=postgres-replica2" --filter "name=postgres-exporter" \
	           --filter "name=node-exporter" \
	           --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

logs-replica2:
	docker logs -f postgres-replica2

status-replica2:
	@echo "=== Replica2 status ==="
	@docker exec postgres-replica2 psql -U $(PGUSER) -c \
	  "SELECT pg_is_in_recovery() AS is_replica, \
	          pg_last_wal_receive_lsn() AS received, \
	          pg_last_wal_replay_lsn() AS replayed, \
	          now() - pg_last_xact_replay_timestamp() AS lag;" || true

# ============================================================
# VM4 — HAPROXY (10.70.16.234)
# ============================================================
up-haproxy:
	cd docker-compose/haproxy && docker compose --env-file ../../$(ENV_FILE) up -d
	@sleep 3
	@$(MAKE) --no-print-directory ps-haproxy

down-haproxy:
	cd docker-compose/haproxy && docker compose --env-file ../../$(ENV_FILE) down

ps-haproxy:
	@docker ps --filter "name=haproxy" --filter "name=node-exporter" \
	           --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

logs-haproxy:
	docker logs -f haproxy

status-haproxy:
	@echo "=== HAProxy stats ==="
	@curl -s http://localhost:$(STATS_PORT) 2>/dev/null | \
	  grep -oE '(pg_primary|pg_replicas|pg_all_nodes|primary|replica[12])' | sort -u || \
	  echo "  Open http://$(VM4_IP):$(STATS_PORT) in browser"
	@echo ""
	@echo "=== Backend TCP reachability ==="
	@echo -n "  Primary  $(VM1_IP):5432 → "; \
	  (nc -z -w2 $(VM1_IP) 5432 && echo UP) || echo DOWN
	@echo -n "  Replica1 $(VM2_IP):5432 → "; \
	  (nc -z -w2 $(VM2_IP) 5432 && echo UP) || echo DOWN
	@echo -n "  Replica2 $(VM3_IP):5432 → "; \
	  (nc -z -w2 $(VM3_IP) 5432 && echo UP) || echo DOWN

# ============================================================
# VM5 — MONITORING (10.70.16.235)
# ============================================================
up-monitoring:
	cd docker-compose/monitoring && docker compose --env-file ../../$(ENV_FILE) up -d
	@sleep 3
	@$(MAKE) --no-print-directory ps-monitoring

down-monitoring:
	cd docker-compose/monitoring && docker compose --env-file ../../$(ENV_FILE) down

ps-monitoring:
	@docker ps --filter "name=prometheus" --filter "name=grafana" \
	           --filter "name=alertmanager" --filter "name=node-exporter" \
	           --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

logs-monitoring:
	docker logs -f prometheus

status-monitoring:
	@echo "=== Prometheus targets ==="
	@curl -s http://localhost:$(PROM_PORT)/api/v1/targets 2>/dev/null | \
	  jq -r '.data.activeTargets[] | "\(.labels.instance) | \(.health)"' || \
	  echo "  Prometheus not reachable. Open http://$(VM5_IP):$(PROM_PORT)/targets"
	@echo ""
	@echo "=== Grafana health ==="
	@curl -s http://localhost:$(GRAFANA_PORT)/api/health 2>/dev/null | jq || \
	  echo "  Grafana not reachable. Open http://$(VM5_IP):$(GRAFANA_PORT)"

# ============================================================
# ALL VMs (one-shot — run from a machine that can SSH to all)
# ============================================================
up-all:
	@echo ">>> Starting cluster in order..."
	@echo "--- VM1: Primary ---"
	ssh root@$(VM1_IP) "cd postgres-ha-cluster && make up-primary"
	@sleep 15
	@echo "--- VM2: Replica1 ---"
	ssh root@$(VM2_IP) "cd postgres-ha-cluster && make up-replica1"
	@echo "--- VM3: Replica2 ---"
	ssh root@$(VM3_IP) "cd postgres-ha-cluster && make up-replica2"
	@sleep 10
	@echo "--- VM4: HAProxy ---"
	ssh root@$(VM4_IP) "cd postgres-ha-cluster && make up-haproxy"
	@echo "--- VM5: Monitoring ---"
	ssh root@$(VM5_IP) "cd postgres-ha-cluster && make up-monitoring"
	@echo ">>> Cluster is up."

down-all:
	@echo ">>> Stopping cluster in reverse order..."
	ssh root@$(VM5_IP) "cd postgres-ha-cluster && make down-monitoring" || true
	ssh root@$(VM4_IP) "cd postgres-ha-cluster && make down-haproxy"  || true
	ssh root@$(VM3_IP) "cd postgres-ha-cluster && make down-replica2" || true
	ssh root@$(VM2_IP) "cd postgres-ha-cluster && make down-replica1" || true
	ssh root@$(VM1_IP) "cd postgres-ha-cluster && make down-primary"  || true

# ============================================================
# TESTS
# ============================================================
test-write:
	@echo "=== Write via HAProxy :$(WRITE_PORT) (VM4) ==="
	@PGPASSWORD="$${POSTGRES_PASSWORD}" psql \
	  -h $(VM4_IP) -p $(WRITE_PORT) -U $(PGUSER) -d $(PGDATABASE) \
	  -c "INSERT INTO test_replication (data) VALUES ('test ' || now());"

test-read:
	@echo "=== Read via HAProxy :$(READ_PORT) (VM4) ==="
	@for i in 1 2 3 4; do \
	  echo -n "  Request $$i → "; \
	  PGPASSWORD="$${POSTGRES_PASSWORD}" psql \
	    -h $(VM4_IP) -p $(READ_PORT) -U $(PGUSER) -d $(PGDATABASE) \
	    -t -A -c "SELECT inet_server_addr() || ' | is_replica=' || pg_is_in_recovery();"; \
	done

test-balance: test-read

test-failover:
	@echo "=== Failover test: stopping replica1 on VM2 ==="
	ssh root@$(VM2_IP) "cd postgres-ha-cluster/docker-compose/replica1 && \
	  docker compose --env-file ../../.env stop postgres-replica1"
	@sleep 4
	@echo "--- All read requests should hit replica2 ---"
	@for i in 1 2 3; do \
	  echo -n "  Request $$i → "; \
	  PGPASSWORD="$${POSTGRES_PASSWORD}" psql \
	    -h $(VM4_IP) -p $(READ_PORT) -U $(PGUSER) -d $(PGDATABASE) \
	    -t -A -c "SELECT inet_server_addr();"; \
	done
	@echo "=== Restarting replica1 ==="
	ssh root@$(VM2_IP) "cd postgres-ha-cluster/docker-compose/replica1 && \
	  docker compose --env-file ../../.env start postgres-replica1"
	@sleep 5
	@echo "=== Done ==="

test-replication:
	@echo "=== WAL streaming check (Primary) ==="
	@ssh root@$(VM1_IP) "docker exec postgres-primary psql -U $(PGUSER) -c \
	  \"SELECT client_addr, state, sync_state FROM pg_stat_replication;\""

test-monitoring:
	@echo "=== Prometheus targets on VM5 ==="
	@curl -s http://$(VM5_IP):$(PROM_PORT)/api/v1/targets | \
	  jq -r '.data.activeTargets[] | "\(.labels.job) \(.labels.instance) → \(.health)"'

test-ha-stats:
	@echo "=== HAProxy backends ==="
	@curl -s http://$(VM4_IP):$(STATS_PORT)/\;csv 2>/dev/null | \
	  awk -F, 'NR>1 && $2!="" {printf "%-20s %-10s %s\n", $1, $2, $18}' | \
	  grep -v "^$" | head -20

# ============================================================
# UTILITIES
# ============================================================
check-firewall:
	@echo "=== VM1 (Primary $(VM1_IP)) ==="
	@echo "  22, 5432, 9100, 9187"
	@echo "=== VM2 (Replica1 $(VM2_IP)) ==="
	@echo "  22, 5432, 9100, 9187"
	@echo "=== VM3 (Replica2 $(VM3_IP)) ==="
	@echo "  22, 5432, 9100, 9187"
	@echo "=== VM4 (HAProxy $(VM4_IP)) ==="
	@echo "  22, 5000, 5001, 5002, 7000, 9100"
	@echo "=== VM5 (Monitoring $(VM5_IP)) ==="
	@echo "  22, 9090, 3000, 9093, 9100"

clean:
	@if [ -z "$(HOST_ROLE)" ]; then \
	  echo "ERROR: Set HOST_ROLE=primary|replica1|replica2|haproxy|monitoring"; \
	  exit 1; \
	fi
	cd docker-compose/$(HOST_ROLE) && docker compose --env-file ../../$(ENV_FILE) down -v
	@echo ">>> Volumes removed for $(HOST_ROLE)"

clean-all: clean
	docker system prune -f
	@echo ">>> Docker system pruned"