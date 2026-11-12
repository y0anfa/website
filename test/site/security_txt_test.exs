defmodule Site.SecurityTxtTest do
  use ExUnit.Case, async: true

  alias Site.{Config, SecurityTxt}

  defp fields do
    for line <- String.split(SecurityTxt.render(), "\n", trim: true),
        not String.starts_with?(line, "#") do
      [name, value] = String.split(line, ": ", parts: 2)
      {name, value}
    end
  end

  test "it lives where RFC 9116 says" do
    assert SecurityTxt.path() == ".well-known/security.txt"
  end

  test "one comment, then a contact, an expiry and its own address" do
    text = SecurityTxt.render()
    assert String.ends_with?(text, "\n")
    assert [comment | _] = String.split(text, "\n")
    assert String.starts_with?(comment, "# ")
    assert length(Regex.scan(~r/^#/m, text)) == 1

    assert fields() == [
             {"Contact", Config.linkedin()},
             {"Expires", "2027-11-01T00:00:00Z"},
             {"Canonical", "https://yoanfaure.com/.well-known/security.txt"}
           ]
  end

  test "the contact is the one the site already shows, over https" do
    assert {"Contact", "https://" <> _} = List.keyfind(fields(), "Contact", 0)
  end

  test "it has not expired, and the date is under a year away" do
    {"Expires", value} = List.keyfind(fields(), "Expires", 0)
    {:ok, expires, 0} = DateTime.from_iso8601(value)
    days = DateTime.diff(expires, DateTime.utc_now(), :day)

    assert days > 0,
           "security.txt has expired: move Site.Config.security_expires/0 forward (and this file's date)"

    assert days < 366
  end

  test "the output is the same every time" do
    assert SecurityTxt.render() == SecurityTxt.render()
  end
end
