defmodule ConnectorWeb.PageController do
  use ConnectorWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
