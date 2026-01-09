defmodule TradingStrategyWeb.UserSocket do
  @moduledoc """
  WebSocket handler for Phoenix Channels.

  Provides transport for real-time communication with clients,
  supporting both WebSocket and long-polling connections.

  ## Channels

  - TradingChannel: Real-time paper trading updates

  ## Authentication

  Currently configured for development without authentication.
  In production, implement token-based authentication in connect/3.
  """

  use Phoenix.Socket

  # Channels
  channel "trading:*", TradingStrategyWeb.TradingChannel

  @impl true
  def connect(_params, socket, _connect_info) do
    # For development, allow all connections
    # In production, validate authentication token:
    #
    # case verify_token(params["token"]) do
    #   {:ok, user_id} ->
    #     {:ok, assign(socket, :user_id, user_id)}
    #   {:error, _reason} ->
    #     :error
    # end

    {:ok, socket}
  end

  @impl true
  def id(_socket), do: nil

  # If you want to track user sessions, implement id/1:
  #
  # def id(socket), do: "user_socket:#{socket.assigns.user_id}"
  #
  # This would enable features like:
  # - Disconnecting all user sessions: TradingStrategyWeb.Endpoint.broadcast("user_socket:#{user_id}", "disconnect", %{})
end
