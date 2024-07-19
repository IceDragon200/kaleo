defmodule Kaleo.Repo do
  use Ecto.Repo,
    otp_app: :kaleo,
    adapter: Ecto.Adapters.Postgres
end
