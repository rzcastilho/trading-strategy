defmodule TradingStrategyWeb.Router do
  use TradingStrategyWeb, :router

  import TradingStrategyWeb.UserAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {TradingStrategyWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_scope_for_user
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/api", TradingStrategyWeb do
    pipe_through :api

    # Strategy Management (US1: Define Strategy Using DSL)
    resources "/strategies", StrategyController, except: [:new, :edit]

    # Backtest Management (US2: Backtest Strategy)
    resources "/backtests", BacktestController, except: [:new, :edit, :update] do
      get "/progress", BacktestController, :show_progress
    end

    # Data Quality Validation
    post "/backtests/validate-data", BacktestController, :validate_data

    # Paper Trading Management (US3: Paper Trading)
    scope "/paper_trading" do
      # Session management
      post "/sessions", PaperTradingController, :create
      get "/sessions", PaperTradingController, :index
      get "/sessions/:id", PaperTradingController, :show
      delete "/sessions/:id", PaperTradingController, :delete

      # Session control
      post "/sessions/:id/pause", PaperTradingController, :pause
      post "/sessions/:id/resume", PaperTradingController, :resume

      # Session data
      get "/sessions/:id/trades", PaperTradingController, :trades
      get "/sessions/:id/metrics", PaperTradingController, :metrics
    end

    # Live Trading Management (US4: Live Trading with Exchange Integration)
    scope "/live_trading" do
      # Session management
      post "/sessions", LiveTradingController, :create
      get "/sessions", LiveTradingController, :index
      get "/sessions/:id", LiveTradingController, :show
      delete "/sessions/:id", LiveTradingController, :delete

      # Session control
      post "/sessions/:id/pause", LiveTradingController, :pause
      post "/sessions/:id/resume", LiveTradingController, :resume
      post "/sessions/:id/emergency_stop", LiveTradingController, :emergency_stop

      # Order management
      post "/sessions/:id/orders", LiveTradingController, :place_order
      get "/sessions/:id/orders/:order_id", LiveTradingController, :get_order
      delete "/sessions/:id/orders/:order_id", LiveTradingController, :cancel_order
    end
  end

  scope "/", TradingStrategyWeb do
    pipe_through :browser

    live "/paper_trading", PaperTradingLive
    live "/paper_trading/:session_id", PaperTradingLive
  end

  ## Authentication routes

  scope "/", TradingStrategyWeb do
    pipe_through [:browser, :require_authenticated_user]

    live_session :require_authenticated_user,
      on_mount: [{TradingStrategyWeb.UserAuth, :require_authenticated}] do
      live "/users/settings", UserLive.Settings, :edit
      live "/users/settings/confirm-email/:token", UserLive.Settings, :confirm_email

      # Strategy Management UI (Feature 004)
      live "/strategies", StrategyLive.Index, :index
      live "/strategies/new", StrategyLive.Form, :new
      live "/strategies/:id", StrategyLive.Show, :show
      live "/strategies/:id/edit", StrategyLive.Form, :edit
    end

    post "/users/update-password", UserSessionController, :update_password
  end

  scope "/", TradingStrategyWeb do
    pipe_through [:browser]

    live_session :current_user,
      on_mount: [{TradingStrategyWeb.UserAuth, :mount_current_scope}] do
      live "/users/register", UserLive.Registration, :new
      live "/users/log-in", UserLive.Login, :new
      live "/users/log-in/:token", UserLive.Confirmation, :new
    end

    post "/users/log-in", UserSessionController, :create
    delete "/users/log-out", UserSessionController, :delete
  end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:trading_strategy, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: TradingStrategyWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
