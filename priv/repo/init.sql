-- Enable TimescaleDB extension
CREATE EXTENSION IF NOT EXISTS timescaledb CASCADE;

-- Set timezone to UTC for consistency
SET timezone = 'UTC';
