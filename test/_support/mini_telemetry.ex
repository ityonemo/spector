defmodule SpectorTest.MiniTelemetry do
  @moduledoc false

  def attach(handler_id, event_name) do
    :telemetry.attach(
      handler_id,
      event_name,
      &__MODULE__.handle_event/4,
      %{pid: self()}
    )
  end

  def detach(handler_id) do
    :telemetry.detach(handler_id)
  end

  def handle_event(event_name, measurements, metadata, %{pid: pid}) do
    send(pid, {:telemetry_event, event_name, measurements, metadata})
  end
end
