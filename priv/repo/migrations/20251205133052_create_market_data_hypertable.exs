defmodule TradingStrategy.Repo.Migrations.CreateMarketDataHypertable do
  use Ecto.Migration

  def up do
    create table(:market_data, primary_key: false) do
      add :symbol, :string, null: false
      add :exchange, :string, null: false
      add :timeframe, :string, null: false
      add :timestamp, :utc_datetime_usec, null: false
      add :open, :decimal, precision: 20, scale: 8, null: false
      add :high, :decimal, precision: 20, scale: 8, null: false
      add :low, :decimal, precision: 20, scale: 8, null: false
      add :close, :decimal, precision: 20, scale: 8, null: false
      add :volume, :decimal, precision: 20, scale: 8, null: false

      timestamps(type: :utc_datetime_usec)
    end

    # Create composite primary key including timestamp for TimescaleDB
    execute "ALTER TABLE market_data ADD PRIMARY KEY (symbol, exchange, timeframe, timestamp);"

    # Create TimescaleDB hypertable partitioned by timestamp
    execute """
    SELECT create_hypertable('market_data', 'timestamp',
      chunk_time_interval => INTERVAL '1 day',
      if_not_exists => TRUE
    );
    """

    # Create indexes for common queries
    create index(:market_data, [:timestamp])
    create index(:market_data, [:symbol, :timestamp])
  end

  def down do
    drop table(:market_data)
  end
end
