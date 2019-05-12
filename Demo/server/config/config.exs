# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.
use Mix.Config

# General application configuration
config :godot_server,
  ecto_repos: [GodotServer.Repo]

# Configures the endpoint
config :godot_server, GodotServerWeb.Endpoint,
  url: [host: "localhost"],
  secret_key_base: "Ye1yX6e15nLiIuTj3HfJv2GWn7yiCeXwUVwQko1HzEUlP1haBwpnBpB8w/WqZNur",
  render_errors: [view: GodotServerWeb.ErrorView, accepts: ~w(html json)],
  pubsub: [name: GodotServer.PubSub,
           adapter: Phoenix.PubSub.PG2]

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{Mix.env}.exs"
