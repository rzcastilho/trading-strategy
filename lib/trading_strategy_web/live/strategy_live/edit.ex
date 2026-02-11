defmodule TradingStrategyWeb.StrategyLive.Edit do
  @moduledoc """
  LiveView for bidirectional strategy editing (Feature 005).

  Provides real-time synchronization between:
  - Advanced Strategy Builder (visual form interface)
  - Manual DSL Editor (code editor)

  Features:
  - Bidirectional sync (builder ↔ DSL)
  - Undo/redo support across both editors
  - Comment preservation
  - Validation and error handling
  - Explicit save (no autosave, FR-020)
  """

  use TradingStrategyWeb, :live_view

  alias TradingStrategy.StrategyEditor.{
    StrategyDefinition,
    BuilderState,
    EditHistory,
    ValidationResult,
    Synchronizer,
    ChangeEvent,
    Validator
  }

  alias TradingStrategy.Repo

  require Logger

  # Configuration
  @debounce_delay Application.compile_env(
                    :trading_strategy,
                    [:strategy_editor, :debounce_delay],
                    300
                  )
  @sync_timeout Application.compile_env(:trading_strategy, [:strategy_editor, :sync_timeout], 500)

  # Mount and Setup

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    strategy = load_strategy(id, socket.assigns.current_scope.user)

    if connected?(socket) do
      # Start editing session for undo/redo
      {:ok, session_id} =
        EditHistory.start_session(
          strategy.id,
          socket.assigns.current_scope.user.id
        )

      socket =
        socket
        |> assign(:strategy, strategy)
        |> assign(:session_id, session_id)
        |> assign(:builder_state, strategy.builder_state || BuilderState.new())
        |> assign(:dsl_text, strategy.dsl_text || "")
        |> assign(:last_modified_editor, strategy.last_modified_editor || :builder)
        |> assign(:validation_result, ValidationResult.success())
        |> assign(:sync_status, :idle)
        |> assign(:unsaved_changes, false)
        |> assign(:can_undo, false)
        |> assign(:can_redo, false)
        |> assign(:sync_in_progress, false)
        |> assign(:last_modified_at, DateTime.utc_now())

      {:ok, socket}
    else
      # Initial render before connection
      socket =
        socket
        |> assign(:strategy, strategy)
        |> assign(:session_id, nil)
        |> assign(:builder_state, strategy.builder_state || BuilderState.new())
        |> assign(:dsl_text, strategy.dsl_text || "")
        |> assign(:last_modified_editor, strategy.last_modified_editor || :builder)
        |> assign(:validation_result, ValidationResult.success())
        |> assign(:sync_status, :idle)
        |> assign(:unsaved_changes, false)
        |> assign(:can_undo, false)
        |> assign(:can_redo, false)
        |> assign(:sync_in_progress, false)
        |> assign(:last_modified_at, DateTime.utc_now())

      {:ok, socket}
    end
  end

  @impl true
  def mount(_params, _session, socket) do
    # New strategy creation
    user = socket.assigns.current_scope.user

    strategy = %StrategyDefinition{
      user_id: user.id,
      name: "",
      dsl_text: "",
      builder_state: BuilderState.new(),
      last_modified_editor: :builder,
      validation_status: ValidationResult.success() |> ValidationResult.to_map()
    }

    if connected?(socket) do
      {:ok, session_id} = EditHistory.start_session(nil, user.id)

      socket =
        socket
        |> assign(:strategy, strategy)
        |> assign(:session_id, session_id)
        |> assign(:builder_state, BuilderState.new())
        |> assign(:dsl_text, "")
        |> assign(:last_modified_editor, :builder)
        |> assign(:validation_result, ValidationResult.success())
        |> assign(:sync_status, :idle)
        |> assign(:unsaved_changes, false)
        |> assign(:can_undo, false)
        |> assign(:can_redo, false)
        |> assign(:sync_in_progress, false)
        |> assign(:last_modified_at, DateTime.utc_now())

      {:ok, socket}
    else
      socket =
        socket
        |> assign(:strategy, strategy)
        |> assign(:session_id, nil)
        |> assign(:builder_state, BuilderState.new())
        |> assign(:dsl_text, "")
        |> assign(:last_modified_editor, :builder)
        |> assign(:validation_result, ValidationResult.success())
        |> assign(:sync_status, :idle)
        |> assign(:unsaved_changes, false)
        |> assign(:can_undo, false)
        |> assign(:can_redo, false)
        |> assign(:sync_in_progress, false)
        |> assign(:last_modified_at, DateTime.utc_now())

      {:ok, socket}
    end
  end

  # Event Handlers

  @impl true
  def handle_event("builder_changed", %{"builder_state" => builder_params}, socket) do
    # T028: Builder changes with 300ms debouncing
    # T073: Synchronization lock to prevent simultaneous syncs
    # This event is triggered when the builder form changes
    # Rate limiting: 300ms client-side debounce + server-side rate limit

    # T073: Check if sync is already in progress
    if socket.assigns[:sync_in_progress] do
      Logger.debug("Builder change dropped: sync already in progress")
      {:noreply, socket}
    else
      # Server-side rate limiting (FR-008)
      last_sync = socket.assigns[:last_sync_at] || 0
      now = System.monotonic_time(:millisecond)

      if now - last_sync < @debounce_delay do
        # Too soon, drop this event
        Logger.debug("Builder change dropped: rate limited")
        {:noreply, socket}
      else
        Logger.debug("Builder changed: #{inspect(Map.keys(builder_params))}")

        # T073: Set sync in progress flag
        socket = assign(socket, :sync_in_progress, true)

        # Parse builder params into BuilderState
        builder_state = parse_builder_params(builder_params, socket.assigns.builder_state)

        # Sync to DSL editor using Synchronizer
        case Synchronizer.builder_to_dsl(builder_state, builder_state._comments) do
          {:ok, dsl_text} ->
            # Create change event for undo/redo
            change_event = %ChangeEvent{
              id: Ecto.UUID.generate(),
              session_id: socket.assigns.session_id,
              timestamp: now,
              source: :builder,
              operation_type: :builder_update,
              path: [],
              delta: {socket.assigns.builder_state, builder_state},
              inverse: {builder_state, socket.assigns.builder_state},
              user_id: socket.assigns.current_scope.user.id,
              version: (socket.assigns.builder_state._version || 0) + 1
            }

            # Push to undo stack
            EditHistory.push(socket.assigns.session_id, change_event)

            socket =
              socket
              |> assign(:builder_state, %{builder_state | _version: change_event.version})
              |> assign(:dsl_text, dsl_text)
              |> assign(:last_modified_editor, :builder)
              |> assign(:last_modified_at, DateTime.utc_now(:microsecond))
              |> assign(:last_sync_at, now)
              |> assign(:unsaved_changes, true)
              |> assign(:sync_status, :success)
              |> assign(:sync_in_progress, false)
              |> assign(:can_undo, EditHistory.can_undo?(socket.assigns.session_id))
              |> assign(:can_redo, EditHistory.can_redo?(socket.assigns.session_id))
              |> push_event("dsl_updated", %{dsl_text: dsl_text})

            # Clear sync status after 1 second
            Process.send_after(self(), :clear_sync_status, 1000)

            {:noreply, socket}

          {:error, reason} ->
            Logger.error("Builder → DSL sync failed: #{reason}")

            socket =
              socket
              |> assign(:sync_status, :error)
              |> assign(:sync_in_progress, false)
              |> put_flash(:error, "Synchronization failed: #{reason}")

            {:noreply, socket}
        end
      end
    end
  end

  @impl true
  def handle_event("dsl_changed", %{"dsl_text" => dsl_text}, socket) do
    # T041: DSL changes with 300ms debouncing and server-side rate limiting
    # T057: Preserve last valid builder state on error (FR-005)
    # T073: Synchronization lock to prevent simultaneous syncs
    # This event is triggered when the DSL editor changes
    # Rate limiting: minimum 300ms between syncs (FR-008)

    # T073: Check if sync is already in progress
    if socket.assigns[:sync_in_progress] do
      Logger.debug("DSL change dropped: sync already in progress")
      {:noreply, socket}
    else
      now = System.monotonic_time(:millisecond)
      last_sync = socket.assigns[:last_dsl_sync_at] || 0
      # milliseconds
      min_interval = 300

      if now - last_sync >= min_interval do
        Logger.debug("DSL changed: #{String.length(dsl_text)} characters")

        # T073: Set sync in progress flag
        socket = assign(socket, :sync_in_progress, true)

        # Validate DSL first (T057)
        validation_result = Validator.validate(dsl_text)

        if validation_result.valid do
          # Valid DSL - proceed with sync
          case Synchronizer.dsl_to_builder(dsl_text) do
            {:ok, builder_state} ->
              # Successfully parsed and converted to builder state
              Logger.debug("DSL → Builder sync successful")

              # Push change event to undo stack
              change_event = %ChangeEvent{
                session_id: socket.assigns.session_id,
                source: :dsl,
                operation_type: :update_dsl_text,
                path: ["dsl_text"],
                delta: {socket.assigns.dsl_text, dsl_text},
                user_id: socket.assigns.current_user.id,
                version: (socket.assigns[:version] || 0) + 1
              }

              EditHistory.push(socket.assigns.session_id, change_event)

              socket =
                socket
                |> assign(:dsl_text, dsl_text)
                |> assign(:builder_state, builder_state)
                |> assign(:last_modified_editor, :dsl)
                |> assign(:last_modified_at, DateTime.utc_now())
                |> assign(:last_dsl_sync_at, now)
                |> assign(:unsaved_changes, true)
                |> assign(:sync_status, :success)
                |> assign(:sync_in_progress, false)
                |> assign(:validation_result, validation_result)
                |> assign(:sync_error, nil)
                |> assign(:can_undo, EditHistory.can_undo?(socket.assigns.session_id))
                |> assign(:can_redo, EditHistory.can_redo?(socket.assigns.session_id))
                |> assign(:version, change_event.version)

              {:noreply, socket}

            {:error, reason} ->
              # Parse error - preserve last valid builder state (FR-005)
              Logger.warning("DSL parse error: #{reason}")

              socket =
                socket
                |> assign(:dsl_text, dsl_text)
                |> assign(:last_modified_editor, :dsl)
                |> assign(:last_modified_at, DateTime.utc_now())
                |> assign(:last_dsl_sync_at, now)
                |> assign(:sync_status, :error)
                |> assign(:sync_in_progress, false)
                |> assign(:validation_result, validation_result)
                |> assign(:sync_error, reason)

              # Keep builder_state unchanged (last valid state preserved - FR-005)

              {:noreply, socket}
          end
        else
          # Invalid DSL - preserve last valid builder state (T057, FR-005)
          Logger.warning("DSL validation failed: #{length(validation_result.errors)} errors")

          socket =
            socket
            |> assign(:dsl_text, dsl_text)
            |> assign(:last_modified_editor, :dsl)
            |> assign(:last_modified_at, DateTime.utc_now())
            |> assign(:last_dsl_sync_at, now)
            |> assign(:sync_status, :error)
            |> assign(:sync_in_progress, false)
            |> assign(:validation_result, validation_result)

          # Keep builder_state unchanged (last valid state preserved - FR-005)

          {:noreply, socket}
        end
      else
        # Rate limit exceeded - drop this event
        Logger.debug("DSL sync rate limited (too frequent)")
        {:noreply, socket}
      end
    end
  end

  @impl true
  def handle_event("validate_dsl", _params, socket) do
    # T056: Manual DSL validation trigger
    # Allows users to explicitly validate DSL without syncing
    Logger.debug("Manual DSL validation triggered")

    dsl_text = socket.assigns.dsl_text
    validation_result = Validator.validate(dsl_text)

    Logger.debug(
      "Validation result: #{validation_result.valid}, errors: #{length(validation_result.errors)}, warnings: #{length(validation_result.warnings)}"
    )

    socket =
      socket
      |> assign(:validation_result, validation_result)
      |> assign(:sync_status, if(validation_result.valid, do: :success, else: :error))

    {:noreply, socket}
  end

  @impl true
  def handle_event("undo", _params, socket) do
    # T016: Undo event handler (FR-012)
    # Undo the last change from the shared undo stack

    case EditHistory.undo(socket.assigns.session_id) do
      {:ok, event} ->
        Logger.info("Undo event: #{event.operation_type}")

        # TODO: Apply the inverse change to the current state
        # TODO: Update both builder and DSL to reflect the undone change

        socket =
          socket
          |> assign(:unsaved_changes, true)
          |> assign(:can_undo, EditHistory.can_undo?(socket.assigns.session_id))
          |> assign(:can_redo, EditHistory.can_redo?(socket.assigns.session_id))
          |> put_flash(:info, "Undone")

        {:noreply, socket}

      {:error, :nothing_to_undo} ->
        {:noreply, put_flash(socket, :info, "Nothing to undo")}

      {:error, reason} ->
        Logger.error("Undo failed: #{inspect(reason)}")
        {:noreply, put_flash(socket, :error, "Undo failed")}
    end
  end

  @impl true
  def handle_event("redo", _params, socket) do
    # T016: Redo event handler (FR-012)
    # Redo the last undone change from the redo stack

    case EditHistory.redo(socket.assigns.session_id) do
      {:ok, event} ->
        Logger.info("Redo event: #{event.operation_type}")

        # TODO: Apply the change to the current state
        # TODO: Update both builder and DSL to reflect the redone change

        socket =
          socket
          |> assign(:unsaved_changes, true)
          |> assign(:can_undo, EditHistory.can_undo?(socket.assigns.session_id))
          |> assign(:can_redo, EditHistory.can_redo?(socket.assigns.session_id))
          |> put_flash(:info, "Redone")

        {:noreply, socket}

      {:error, :nothing_to_redo} ->
        {:noreply, put_flash(socket, :info, "Nothing to redo")}

      {:error, reason} ->
        Logger.error("Redo failed: #{inspect(reason)}")
        {:noreply, put_flash(socket, :error, "Redo failed")}
    end
  end

  @impl true
  def handle_event("save_strategy", _params, socket) do
    # T017: Explicit save handler (FR-020 - no autosave)
    # Save the strategy to the database

    strategy = socket.assigns.strategy
    last_modified_editor = socket.assigns.last_modified_editor

    # Determine what to save based on last modified editor
    attrs =
      case last_modified_editor do
        :builder ->
          %{
            builder_state: socket.assigns.builder_state,
            last_modified_editor: :builder,
            last_modified_at: DateTime.utc_now(:microsecond)
          }

        :dsl ->
          %{
            dsl_text: socket.assigns.dsl_text,
            last_modified_editor: :dsl,
            last_modified_at: DateTime.utc_now(:microsecond)
          }
      end

    changeset =
      if strategy.id do
        StrategyDefinition.update_changeset(strategy, attrs)
      else
        StrategyDefinition.changeset(strategy, Map.put(attrs, :name, "Untitled Strategy"))
      end

    case Repo.insert_or_update(changeset) do
      {:ok, updated_strategy} ->
        Logger.info("Strategy saved: #{updated_strategy.id}")

        socket =
          socket
          |> assign(:strategy, updated_strategy)
          |> assign(:unsaved_changes, false)
          |> put_flash(:info, "Strategy saved successfully")

        {:noreply, socket}

      {:error, changeset} ->
        Logger.error("Save failed: #{inspect(changeset.errors)}")

        socket =
          socket
          |> put_flash(:error, "Failed to save strategy")

        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("validate_dsl", _params, socket) do
    # T056: Manual validation trigger
    # Validate the DSL text and display errors

    # TODO: Implement validation using Validator module

    socket =
      socket
      |> assign(:validation_result, ValidationResult.success())
      |> put_flash(:info, "Validation passed")

    {:noreply, socket}
  end

  # Message Handlers

  @impl true
  def handle_info(:clear_sync_status, socket) do
    {:noreply, assign(socket, :sync_status, :idle)}
  end

  # Lifecycle Callbacks

  @impl true
  def terminate(_reason, socket) do
    # Clean up: end the editing session
    if socket.assigns[:session_id] do
      EditHistory.end_session(socket.assigns.session_id)
    end

    :ok
  end

  # Helper Functions

  defp parse_builder_params(params, current_state) do
    # Parse incoming builder form parameters into BuilderState struct
    # This merges new changes with existing state

    indicators =
      case params["indicators"] do
        indicators_list when is_list(indicators_list) ->
          Enum.map(indicators_list, fn ind ->
            %BuilderState.Indicator{
              type: ind["type"],
              name: ind["name"],
              parameters: ind["parameters"] || %{},
              _id: ind["_id"] || Ecto.UUID.generate()
            }
          end)

        _ ->
          current_state.indicators || []
      end

    position_sizing =
      case params["position_sizing"] do
        %{"type" => type} = ps ->
          %BuilderState.PositionSizing{
            type: type,
            percentage_of_capital: ps["percentage_of_capital"],
            fixed_amount: ps["fixed_amount"],
            _id: ps["_id"] || Ecto.UUID.generate()
          }

        _ ->
          current_state.position_sizing
      end

    risk_parameters =
      case params["risk_parameters"] do
        %{} = rp when map_size(rp) > 0 ->
          %BuilderState.RiskParameters{
            max_daily_loss: rp["max_daily_loss"],
            max_drawdown: rp["max_drawdown"],
            max_position_size: rp["max_position_size"],
            _id: rp["_id"] || Ecto.UUID.generate()
          }

        _ ->
          current_state.risk_parameters
      end

    %BuilderState{
      name: params["name"] || current_state.name,
      trading_pair: params["trading_pair"] || current_state.trading_pair,
      timeframe: params["timeframe"] || current_state.timeframe,
      description: params["description"],
      indicators: indicators,
      entry_conditions: params["entry_conditions"],
      exit_conditions: params["exit_conditions"],
      stop_conditions: params["stop_conditions"],
      position_sizing: position_sizing,
      risk_parameters: risk_parameters,
      _comments: current_state._comments || [],
      _version: (current_state._version || 0) + 1,
      _last_sync_at: DateTime.utc_now()
    }
  end

  defp load_strategy(id, user) do
    case Repo.get(StrategyDefinition, id) do
      nil ->
        raise "Strategy not found"

      strategy ->
        if strategy.user_id == user.id do
          strategy
        else
          raise "Unauthorized"
        end
    end
  end

  # Render Template

  @impl true
  def render(assigns) do
    ~H"""
    <div
      class="strategy-editor h-screen flex flex-col"
      id="editor-container"
      phx-hook="UnsavedChangesHook"
      data-unsaved={@unsaved_changes}
    >
      <!-- Global keyboard shortcuts (invisible) -->
      <div id="keyboard-shortcuts" phx-hook="KeyboardShortcutsHook" style="display: none;"></div>
      <!-- Header -->
      <div class="bg-white shadow-sm border-b px-6 py-4">
        <div class="flex items-center justify-between">
          <div>
            <h1 class="text-2xl font-bold text-gray-900">
              <%= @strategy.name || "Untitled Strategy" %>
            </h1>
            <p class="text-sm text-gray-500">
              Last modified: <%= if @strategy.last_modified_at, do: Calendar.strftime(@strategy.last_modified_at, "%Y-%m-%d %H:%M"), else: "Never" %>
            </p>
          </div>

          <!-- Actions -->
          <div class="flex items-center gap-3">
            <!-- Undo/Redo -->
            <button
              phx-click="undo"
              disabled={!@can_undo}
              class="btn btn-sm btn-ghost"
              title="Undo (Ctrl+Z)"
            >
              ↶ Undo
            </button>

            <button
              phx-click="redo"
              disabled={!@can_redo}
              class="btn btn-sm btn-ghost"
              title="Redo (Ctrl+Shift+Z)"
            >
              ↷ Redo
            </button>

            <!-- Save -->
            <button
              phx-click="save_strategy"
              class={"btn btn-sm btn-primary #{if @unsaved_changes, do: "", else: "btn-disabled"}"}
              title="Save (Ctrl+S)"
            >
              💾 Save
            </button>
          </div>
        </div>

        <!-- Sync Status Indicator (T030 & T031) -->
        <div class="mt-2 min-h-[24px] flex items-center gap-4">
          <div class="flex-1">
            <%= case @sync_status do %>
              <% :syncing -> %>
                <!-- Loading indicator - shows after 200ms (FR-011) -->
                <div class="flex items-center gap-2 text-sm text-blue-600 animate-pulse">
                  <svg class="w-4 h-4 animate-spin" fill="none" viewBox="0 0 24 24">
                    <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
                    <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
                  </svg>
                  <span>Synchronizing...</span>
                </div>

              <% :success -> %>
                <!-- Success indicator - auto-clears after 1s -->
                <div class="flex items-center gap-2 text-sm text-green-600">
                  <svg class="w-4 h-4" fill="currentColor" viewBox="0 0 20 20">
                    <path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zm3.707-9.293a1 1 0 00-1.414-1.414L9 10.586 7.707 9.293a1 1 0 00-1.414 1.414l2 2a1 1 0 001.414 0l4-4z" clip-rule="evenodd"/>
                  </svg>
                  <span>Synced</span>
                </div>

              <% :error -> %>
                <!-- Error indicator -->
                <div class="flex items-center gap-2 text-sm text-red-600">
                  <svg class="w-4 h-4" fill="currentColor" viewBox="0 0 20 20">
                    <path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zM8.707 7.293a1 1 0 00-1.414 1.414L8.586 10l-1.293 1.293a1 1 0 101.414 1.414L10 11.414l1.293 1.293a1 1 0 001.414-1.414L11.414 10l1.293-1.293a1 1 0 00-1.414-1.414L10 8.586 8.707 7.293z" clip-rule="evenodd"/>
                  </svg>
                  <span>Sync failed</span>
                </div>

              <% :idle -> %>
                <!-- No status shown when idle -->
            <% end %>
          </div>

          <!-- T072: Last Modified Editor Indicator (FR-007) -->
          <div class="flex items-center gap-2">
            <span class="text-xs text-gray-500">Last edited in:</span>
            <%= if @last_modified_editor == :builder do %>
              <span class="inline-flex items-center px-2 py-1 text-xs font-medium rounded-full bg-blue-100 text-blue-800">
                <svg class="w-3 h-3 mr-1" fill="currentColor" viewBox="0 0 20 20">
                  <path d="M3 4a1 1 0 011-1h12a1 1 0 011 1v2a1 1 0 01-1 1H4a1 1 0 01-1-1V4zM3 10a1 1 0 011-1h6a1 1 0 011 1v6a1 1 0 01-1 1H4a1 1 0 01-1-1v-6zM14 9a1 1 0 00-1 1v6a1 1 0 001 1h2a1 1 0 001-1v-6a1 1 0 00-1-1h-2z"/>
                </svg>
                Builder
              </span>
            <% else %>
              <span class="inline-flex items-center px-2 py-1 text-xs font-medium rounded-full bg-purple-100 text-purple-800">
                <svg class="w-3 h-3 mr-1" fill="currentColor" viewBox="0 0 20 20">
                  <path fill-rule="evenodd" d="M12.316 3.051a1 1 0 01.633 1.265l-4 12a1 1 0 11-1.898-.632l4-12a1 1 0 011.265-.633zM5.707 6.293a1 1 0 010 1.414L3.414 10l2.293 2.293a1 1 0 11-1.414 1.414l-3-3a1 1 0 010-1.414l3-3a1 1 0 011.414 0zm8.586 0a1 1 0 011.414 0l3 3a1 1 0 010 1.414l-3 3a1 1 0 11-1.414-1.414L16.586 10l-2.293-2.293a1 1 0 010-1.414z" clip-rule="evenodd"/>
                </svg>
                DSL Editor
              </span>
            <% end %>
          </div>
        </div>
      </div>

      <!-- Editor Layout -->
      <div class="flex-1 flex overflow-hidden">
        <!-- Builder Panel (Left) -->
        <div class="w-1/2 border-r overflow-y-auto p-6">
          <h2 class="text-lg font-semibold mb-4">Advanced Strategy Builder</h2>

          <!-- Builder form will go here (T029: BuilderFormHook) -->
          <div id="builder-form" phx-hook="BuilderFormHook" phx-update="ignore">
            <p class="text-gray-500 italic">
              Builder form components will be implemented in Phase 3 (User Story 1)
            </p>
          </div>
        </div>

        <!-- DSL Panel (Right) -->
        <div class="w-1/2 overflow-y-auto p-6">
          <h2 class="text-lg font-semibold mb-4">DSL Editor</h2>

          <!-- DSL editor will go here (T042: DSLEditorHook) -->
          <div
            id="dsl-editor"
            phx-hook="DSLEditorHook"
            phx-update="ignore"
            data-dsl-text={@dsl_text}
            class="border rounded min-h-[400px] font-mono text-sm"
          >
            <textarea
              class="w-full h-full p-4"
              placeholder="# DSL code will appear here..."
              phx-debounce={@debounce_delay}
            ><%= @dsl_text %></textarea>
          </div>

          <!-- Validation Errors -->
          <%= if !ValidationResult.valid?(@validation_result) do %>
            <div class="mt-4 alert alert-error">
              <h3 class="font-semibold">Validation Errors</h3>
              <ul class="list-disc list-inside mt-2">
                <%= for error <- @validation_result.errors do %>
                  <li>
                    Line <%= error.line %>: <%= error.message %>
                  </li>
                <% end %>
              </ul>
            </div>
          <% end %>
        </div>
      </div>
    </div>
    """
  end
end
