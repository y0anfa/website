defmodule Site.Error do
  @moduledoc "Raised when the build cannot continue (bad content, bad options)."
  defexception [:message]
end
