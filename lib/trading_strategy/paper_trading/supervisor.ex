defmodule TradingStrategy.PaperTrading.Supervisor do
  @moduledoc """
  Supervisor for paper trading infrastructure.

  Manages:
  - Session registry for process lookup
  - Session persister for database operations
  - Dynamic supervisor for session processes

  ## Supervision Tree

  ```
  PaperTrading.Supervisor
  ├── SessionRegistry (Registry)
  ├── SessionPersister (GenServer)
  └── SessionSupervisor (DynamicSupervisor)
      ├── SessionManager (session 1)
      ├── SessionManager (session 2)
      └── ...
  ```
  """

  use Supervisor

  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    children = [
      # Registry for session process lookup
      {Registry, keys: :unique, name: TradingStrategy.PaperTrading.SessionRegistry},

      # Session persister for database operations
      TradingStrategy.PaperTrading.SessionPersister,

      # Dynamic supervisor for session processes
      TradingStrategy.PaperTrading.SessionSupervisor
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
