defmodule TradingStrategyWeb.FallbackController do
  @moduledoc """
  Translates controller action results into valid `Plug.Conn` responses.

  See `Phoenix.Controller.action_fallback/1` for more details.
  """
  use TradingStrategyWeb, :controller

  # This clause handles errors returned by Ecto's insert/update/delete.
  def call(conn, {:error, %Ecto.Changeset{} = changeset}) do
    conn
    |> put_status(:unprocessable_entity)
    |> put_view(json: TradingStrategyWeb.ChangesetJSON)
    |> render(:error, changeset: changeset)
  end

  # This clause is an example of how to handle resources that cannot be found.
  def call(conn, {:error, :not_found}) do
    conn
    |> put_status(:not_found)
    |> put_view(json: TradingStrategyWeb.ErrorJSON)
    |> render(:"404")
  end

  # Handle bad request errors
  def call(conn, {:error, {:bad_request, message}}) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: message})
  end

  # Paper trading specific errors
  def call(conn, {:error, :already_paused}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: "Session is already paused"})
  end

  def call(conn, {:error, :already_stopped}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: "Session is already stopped"})
  end

  def call(conn, {:error, :not_paused}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: "Session is not paused"})
  end

  def call(conn, {:error, :data_feed_unavailable}) do
    conn
    |> put_status(:service_unavailable)
    |> json(%{error: "Data feed unavailable", retry_after: 60})
  end

  def call(conn, {:error, :invalid_trading_pair}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: "Invalid trading pair"})
  end

  # Generic error handler for any other errors
  def call(conn, {:error, reason}) when is_atom(reason) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: Atom.to_string(reason)})
  end

  def call(conn, {:error, reason}) when is_binary(reason) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: reason})
  end
end
