defmodule Connector.Discovery.Subdomain do
  @moduledoc """
  Subdomain-based SaaS discovery layer.

  Probes known subdomain patterns (e.g., `{company}.bamboohr.com`,
  `{company}.personio.de`) to detect active SaaS instances.

  This is Layer 2 — active probing via HTTP HEAD requests.
  Uses concurrent tasks for fast parallel probing.
  """

  alias Connector.Discovery.ProviderRegistry

  require Logger

  @type subdomain_result :: %{
          provider_id: atom(),
          provider_name: String.t(),
          detection_method: :subdomain,
          url: String.t(),
          status_code: integer(),
          confidence: :high | :medium | :low
        }

  @doc """
  Probe all known subdomain patterns for a given company slug.

  The slug is typically derived from the company domain (e.g., "acme" from "acme.com").
  Probes all patterns concurrently with a configurable timeout.

  ## Examples

      iex> Connector.Discovery.Subdomain.discover("acme")
      [
        %{provider_id: :bamboohr, provider_name: "BambooHR",
          detection_method: :subdomain, url: "https://acme.bamboohr.com",
          status_code: 200, confidence: :high}
      ]
  """
  @spec discover(String.t(), keyword()) :: [subdomain_result()]
  def discover(slug, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 5_000)

    probes = build_probes(slug)

    probes
    |> Task.async_stream(
      fn {provider, url} -> {provider, probe_url(url, timeout)} end,
      max_concurrency: 20,
      timeout: timeout + 2_000,
      on_timeout: :kill_task
    )
    |> Enum.flat_map(fn
      {:ok, {provider, {:ok, status_code}}} when status_code in 200..399 ->
        url =
          provider.subdomain_templates
          |> List.first()
          |> String.replace("{slug}", slug)

        [
          %{
            provider_id: provider.id,
            provider_name: provider.name,
            detection_method: :subdomain,
            url: "https://#{url}",
            status_code: status_code,
            confidence: confidence_from_status(status_code)
          }
        ]

      {:ok, {_provider, {:ok, _status}}} ->
        []

      {:ok, {_provider, {:error, _reason}}} ->
        []

      {:exit, _reason} ->
        []
    end)
  end

  @doc """
  Extract a company slug from an email domain.

  ## Examples

      iex> Connector.Discovery.Subdomain.slug_from_domain("acme.com")
      "acme"

      iex> Connector.Discovery.Subdomain.slug_from_domain("hello.acme.co.uk")
      "acme"
  """
  @spec slug_from_domain(String.t()) :: String.t()
  def slug_from_domain(domain) do
    domain
    |> String.downcase()
    |> String.split(".")
    |> reject_tlds()
    |> List.first()
    |> Kernel.||("unknown")
  end

  # ── Internal ──

  defp build_probes(slug) do
    ProviderRegistry.subdomain_detectable()
    |> Enum.flat_map(fn provider ->
      Enum.map(provider.subdomain_templates, fn template ->
        url = String.replace(template, "{slug}", slug)
        {provider, "https://#{url}"}
      end)
    end)
  end

  defp probe_url(url, timeout) do
    case Req.head(url, receive_timeout: timeout, connect_options: [timeout: timeout]) do
      {:ok, %Req.Response{status: status}} ->
        {:ok, status}

      {:error, %Req.TransportError{reason: reason}} ->
        {:error, reason}

      {:error, reason} ->
        {:error, reason}
    end
  rescue
    e ->
      Logger.debug("Subdomain probe failed for #{url}: #{Exception.message(e)}")
      {:error, :exception}
  end

  defp confidence_from_status(status) when status in [200, 301, 302], do: :high
  defp confidence_from_status(status) when status in 300..399, do: :medium
  defp confidence_from_status(_), do: :low

  # Common TLDs and country codes to strip
  @tlds ~w(com org net io co uk de at ch nl fr es it se no dk fi be)

  defp reject_tlds(parts) do
    Enum.reject(parts, &(&1 in @tlds))
  end
end
