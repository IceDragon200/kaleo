# Not the correct home for datetime, but meh
defimpl Logfmt.ValueEncoder, for: NaiveDateTime do
  def encode(naive_date_time) do
    NaiveDateTime.to_iso8601(naive_date_time)
  end
end

defimpl Logfmt.ValueEncoder, for: DateTime do
  def encode(date_time) do
    DateTime.to_iso8601(date_time)
  end
end

defimpl Logfmt.ValueEncoder, for: Date do
  def encode(date) do
    Date.to_iso8601(date)
  end
end
