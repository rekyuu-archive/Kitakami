defmodule Kitakami do
  unless File.exists?("_db"), do: File.mkdir("_db")

  def start(_type, _args) do
    import Supervisor.Spec

    children = [supervisor(Kitakami.Bot, [[name: Kitakami.Bot]])]
    {:ok, _pid} = Supervisor.start_link(children, strategy: :one_for_one)
  end  
end
