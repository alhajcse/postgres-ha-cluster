.PHONY: up-primary up-replica1 up-replica2 down-primary down-replica1 down-replica2 logs-primary logs-replica1 logs-replica2 status

up-primary:
	cd docker-compose/primary && docker compose up -d

up-replica1:
	cd docker-compose/replica1 && docker compose up -d

up-replica2:
	cd docker-compose/replica2 && docker compose up -d

down-primary:
	cd docker-compose/primary && docker compose down

down-replica1:
	cd docker-compose/replica1 && docker compose down

down-replica2:
	cd docker-compose/replica2 && docker compose down

logs-primary:
	cd docker-compose/primary && docker compose logs -f

logs-replica1:
	cd docker-compose/replica1 && docker compose logs -f

logs-replica2:
	cd docker-compose/replica2 && docker compose logs -f

status:
	@echo "=== Primary (10.70.16.201) ==="
	@docker exec postgres-primary psql -U postgres -c "SELECT client_addr, state, sync_state FROM pg_stat_replication;" || true
	@echo "=== Replica1 (10.70.16.202) ==="
	@docker exec postgres-replica1 psql -U postgres -c "SELECT pg_is_in_recovery() AS is_replica;" || true
	@echo "=== Replica2 (10.70.16.205) ==="
	@docker exec postgres-replica2 psql -U postgres -c "SELECT pg_is_in_recovery() AS is_replica;" || true