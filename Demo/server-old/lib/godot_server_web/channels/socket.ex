defmodule GodotServerWeb.Socket do
  @context GodotServerWeb.Endpoint
  @max_age 2_419_200
  @salt "GodotServerWeb.Socket.UserToken"

  def create_token(user_id, salt \\ @salt), do:
    Phoenix.Token.sign(@context, salt, %{user_id: user_id})

  def verify_token(token, salt \\ @salt), do:
    Phoenix.Token.verify(@context, salt, token, max_age: @max_age)

  def error(message), do:
    {:error, %{"error" => %{"message" => message}}}
end
