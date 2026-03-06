defmodule Connector.Repo do
  use Ecto.Repo,
    otp_app: :connector,
    adapter: Ecto.Adapters.Postgres
end
