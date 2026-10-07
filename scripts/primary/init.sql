-- Replication user
CREATE ROLE replicator WITH REPLICATION LOGIN PASSWORD '123456';

-- Physical replication slots (one per replica)
SELECT pg_create_physical_replication_slot('replication_slot_1');
SELECT pg_create_physical_replication_slot('replication_slot_2');

-- Sample table for testing
CREATE TABLE IF NOT EXISTS test_replication (
    id SERIAL PRIMARY KEY,
    data TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);
INSERT INTO test_replication (data) VALUES ('hello from primary');