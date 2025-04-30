# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

# :master_nodes is a list of nodes that this node will connect to
# The nodes are defined in the form of a tuple with the node name and the IP address
# The node name is defined in the form of a string with the format "node@ip_address"
config :walkie_tokie, :master_nodes, [
  :"server@10.241.169.206"
  # :"server@10.0.0.84"
]

# config :walkie_tokie,
#   ecto_repos: [WalkieTokie.Repo],
#   generators: [timestamp_type: :utc_datetime]

# Configures the endpoint
port = String.to_integer(System.get_env("PORT") || "4000")

config :walkie_tokie, WalkieTokieWeb.Endpoint,
  url: [host: "localhost", port: port],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: WalkieTokieWeb.ErrorHTML, json: WalkieTokieWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: WalkieTokie.PubSub,
  live_view: [signing_salt: "eZTPIW68"]

# Configures the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :walkie_tokie, WalkieTokie.Mailer, adapter: Swoosh.Adapters.Local

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.17.11",
  walkie_tokie: [
    args:
      ~w(js/app.js --bundle --target=es2017 --outdir=../priv/static/assets --external:/fonts/* --external:/images/*),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "3.4.3",
  walkie_tokie: [
    args: ~w(
      --config=tailwind.config.js
      --input=css/app.css
      --output=../priv/static/assets/app.css
    ),
    cd: Path.expand("../assets", __DIR__)
  ]

# Configures Elixir's Logger
config :logger, backends: [:console, {Appsignal.Logger.Backend, [group: "phoenix"]}]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"

import_config "appsignal.exs"
