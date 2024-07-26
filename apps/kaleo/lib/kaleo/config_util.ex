defmodule Kaleo.ConfigUtil do
  import Record

  defrecord :config_changed_event, :"$config_changed",
    path: nil,
    config: nil
end
