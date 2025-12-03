defmodule Spector.Integrity.HashMismatch do
  @moduledoc """
  Exception raised when hash chain verification fails.

  This indicates that an event's hash does not match the expected hash computed
  from the previous event's hash and the current event's data. This could indicate
  data tampering or corruption.
  """

  defexception [:event_id, :expected_hash, :actual_hash, :message]

  @impl true
  def exception(opts) do
    event_id = Keyword.fetch!(opts, :event_id)
    expected_hash = Keyword.fetch!(opts, :expected_hash)
    actual_hash = Keyword.fetch!(opts, :actual_hash)

    message = """
    Hash chain verification failed for event #{event_id}.

    Expected hash: #{Base.encode16(expected_hash, case: :lower)}
    Actual hash:   #{Base.encode16(actual_hash, case: :lower)}

    This indicates the event data or hash chain has been tampered with or corrupted.
    """

    %__MODULE__{
      event_id: event_id,
      expected_hash: expected_hash,
      actual_hash: actual_hash,
      message: message
    }
  end
end
