defmodule Connector.Discovery.DNS do
  @moduledoc """
  DNS-based SaaS discovery layer.

  Analyzes MX, SPF (TXT), DMARC, and domain verification TXT records
  to identify which SaaS providers a company uses.

  This is Layer 1 — entirely passive, using only public DNS records.
  """

  alias Connector.Discovery.ProviderRegistry

  @type dns_result :: %{
          provider_id: atom(),
          provider_name: String.t(),
          detection_method: :mx | :spf | :txt,
          evidence: String.t(),
          confidence: :high | :medium | :low
        }

  @doc """
  Perform full DNS discovery for a given domain.

  Returns a list of detected providers with evidence and confidence levels.
  """
  @spec discover(String.t()) :: [dns_result()]
  def discover(domain) when is_binary(domain) do
    domain = String.trim(domain) |> String.downcase()

    tasks = [
      Task.async(fn -> discover_mx(domain) end),
      Task.async(fn -> discover_spf(domain) end),
      Task.async(fn -> discover_txt(domain) end)
    ]

    tasks
    |> Task.await_many(10_000)
    |> List.flatten()
    |> Enum.uniq_by(& &1.provider_id)
  end

  @doc "Query MX records and match against provider fingerprints."
  @spec discover_mx(String.t()) :: [dns_result()]
  def discover_mx(domain) do
    case resolve_dns(domain, :mx) do
      {:ok, records} ->
        mx_hosts =
          records
          |> Enum.map(fn {_priority, host} -> to_string(host) |> String.downcase() end)

        ProviderRegistry.dns_detectable()
        |> Enum.flat_map(fn provider ->
          Enum.flat_map(mx_hosts, fn host ->
            if Enum.any?(provider.mx_contains, &String.contains?(host, &1)) do
              [
                %{
                  provider_id: provider.id,
                  provider_name: provider.name,
                  detection_method: :mx,
                  evidence: host,
                  confidence: :high
                }
              ]
            else
              []
            end
          end)
        end)
        |> Enum.uniq_by(& &1.provider_id)

      {:error, _reason} ->
        []
    end
  end

  @doc "Parse SPF record and match includes against provider fingerprints."
  @spec discover_spf(String.t()) :: [dns_result()]
  def discover_spf(domain) do
    case resolve_dns(domain, :txt) do
      {:ok, records} ->
        spf_records =
          records
          |> Enum.map(&List.to_string/1)
          |> Enum.filter(&String.starts_with?(&1, "v=spf1"))

        spf_includes =
          spf_records
          |> Enum.flat_map(fn record ->
            Regex.scan(~r/include:(\S+)/, record)
            |> Enum.map(fn [full, _domain] -> full end)
          end)

        ProviderRegistry.dns_detectable()
        |> Enum.flat_map(fn provider ->
          Enum.flat_map(spf_includes, fn include ->
            if Enum.any?(provider.spf_includes, fn pattern ->
                 String.contains?(include, pattern)
               end) do
              [
                %{
                  provider_id: provider.id,
                  provider_name: provider.name,
                  detection_method: :spf,
                  evidence: include,
                  confidence: :medium
                }
              ]
            else
              []
            end
          end)
        end)
        |> Enum.uniq_by(& &1.provider_id)

      {:error, _reason} ->
        []
    end
  end

  @doc "Check TXT records for domain verification patterns."
  @spec discover_txt(String.t()) :: [dns_result()]
  def discover_txt(domain) do
    case resolve_dns(domain, :txt) do
      {:ok, records} ->
        txt_values =
          records
          |> Enum.map(&List.to_string/1)

        ProviderRegistry.dns_detectable()
        |> Enum.flat_map(fn provider ->
          Enum.flat_map(txt_values, fn txt ->
            if Enum.any?(provider.txt_contains, &String.contains?(txt, &1)) do
              [
                %{
                  provider_id: provider.id,
                  provider_name: provider.name,
                  detection_method: :txt,
                  evidence: String.slice(txt, 0, 80),
                  confidence: :low
                }
              ]
            else
              []
            end
          end)
        end)
        |> Enum.uniq_by(& &1.provider_id)

      {:error, _reason} ->
        []
    end
  end

  # ── Internal DNS resolution ──

  defp resolve_dns(domain, type) do
    charlist_domain = String.to_charlist(domain)

    case :inet_res.lookup(charlist_domain, :in, type) do
      [] -> {:error, :no_records}
      records -> {:ok, records}
    end
  rescue
    e -> {:error, Exception.message(e)}
  end
end
