# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :trading_strategy, :scopes,
  user: [
    default: true,
    module: TradingStrategy.Accounts.Scope,
    assign_key: :current_scope,
    access_path: [:user, :id],
    schema_key: :user_id,
    schema_type: :id,
    schema_table: :users,
    test_data_fixture: TradingStrategy.AccountsFixtures,
    test_setup_helper: :register_and_log_in_user
  ]

config :trading_strategy,
  ecto_repos: [TradingStrategy.Repo],
  generators: [timestamp_type: :utc_datetime]

# Configure the endpoint
config :trading_strategy, TradingStrategyWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [json: TradingStrategyWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: TradingStrategy.PubSub,
  live_view: [signing_salt: "K8jqDwcw"]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
