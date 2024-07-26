# This file is responsible for configuring your umbrella
# and **all applications** and their dependencies with the
# help of the Config module.
#
# Note that all applications in your umbrella share the
# same configuration and dependencies, which is why they
# all use the same configuration file. If you want different
# configurations or dependencies per app, it is best to
# move said applications out of the umbrella.
import Config

# Configure Mix tasks and generators
config :kaleo,
  ecto_repos: [Kaleo.Repo]

# Configures the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :kaleo, Kaleo.Mailer, adapter: Swoosh.Adapters.Local

config :kaleo_web,
  ecto_repos: [Kaleo.Repo],
  generators: [context_app: :kaleo]

# Configures the endpoint
config :kaleo_web, Kaleo.Web.Endpoint,
  url: [host: "localhost"],
  adapter: Phoenix.Endpoint.Cowboy2Adapter,
  render_errors: [
    formats: [html: Kaleo.Web.ErrorHTML, json: Kaleo.Web.ErrorJSON],
    layout: false
  ],
  pubsub_server: Kaleo.PubSub,
  live_view: [signing_salt: "Xii19LNW"]

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.17.11",
  default: [
    args:
      ~w(js/app.js --bundle --target=es2017 --outdir=../priv/static/assets --external:/fonts/* --external:/images/*),
    cd: Path.expand("../apps/kaleo_web/assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "3.3.2",
  default: [
    args: ~w(
      --config=tailwind.config.js
      --input=css/app.css
      --output=../priv/static/assets/app.css
    ),
    cd: Path.expand("../apps/kaleo_web/assets", __DIR__)
  ]

# Configures Elixir's Logger
config :logger, :console,
  format: "$dateT$time level=$level $metadata $message\n",
  metadata: [:file, :line, :method, :path, :action_name, :status, :remote_ip, :host]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
