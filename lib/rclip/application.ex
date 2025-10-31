defmodule Rclip.Application do
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {Rclip.Store, []},
      {Plug.Cowboy, scheme: :http, plug: Rclip.Router, options: [port: 80]}
    ]

    opts = [strategy: :one_for_one, name: Rclip.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
