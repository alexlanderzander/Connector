defmodule Connector.Discovery.Orchestrator do
  @moduledoc """
  Orchestrates the full SaaS stack discovery pipeline.

  Coordinates all discovery layers (DNS, subdomain, well-known, etc.)
  and aggregates results into a unified discovery report. Broadcasts
  real-time progress via Phoenix PubSub for LiveView consumption.

  ## Architecture

  The orchestrator runs as a supervised Task that:
  1. Extracts the domain and slug from the email
  2. Runs all discovery layers concurrently
  3. Broadcasts each discovery hit in real-time
  4. Returns a complete discovery report
  """

  alias Connector.Discovery.{DNS, Subdomain, ProviderRegistry}

  require Logger

  @type discovery_hit :: %{
          provider_id: atom(),
          provider_name: String.t(),
          category: atom(),
          detection_method: atom(),
          evidence: String.t(),
          confidence: :high | :medium | :low,
          auth_type: atom(),
          icon: String.t(),
          color: String.t()
        }

  @type discovery_report :: %{
          email: String.t(),
          domain: String.t(),
          slug: String.t(),
          started_at: DateTime.t(),
          completed_at: DateTime.t() | nil,
          duration_ms: integer() | nil,
          hits: [discovery_hit()],
          layers_completed: [atom()],
          total_providers_checked: integer()
        }

  @pubsub Connector.PubSub
  @topic_prefix "discovery"

  @doc """
  Run full discovery for an email address.

  Runs all discovery layers concurrently, broadcasting each hit
  in real-time via PubSub.

  ## Options

  - `:broadcast` - Whether to broadcast results via PubSub (default: true)
  - `:session_id` - Unique session ID for PubSub topic (auto-generated if nil)

  ## Examples

      iex> Connector.Discovery.Orchestrator.run("alex@acme.com")
      {:ok, %{
        email: "alex@acme.com",
        domain: "acme.com",
        slug: "acme",
        hits: [...],
        duration_ms: 2345
      }}
  """
  @spec run(String.t(), keyword()) :: {:ok, discovery_report()} | {:error, term()}
  def run(email, opts \\ []) do
    broadcast? = Keyword.get(opts, :broadcast, true)
    session_id = Keyword.get(opts, :session_id, generate_session_id())

    with {:ok, domain} <- extract_domain(email) do
      slug = Subdomain.slug_from_domain(domain)
      started_at = DateTime.utc_now()

      if broadcast?,
        do: broadcast(session_id, :discovery_started, %{email: email, domain: domain, slug: slug})

      # Run all discovery layers concurrently
      dns_task =
        Task.async(fn ->
          results = DNS.discover(domain)
          if broadcast?, do: broadcast(session_id, :layer_complete, %{layer: :dns, hits: results})
          {:dns, results}
        end)

      subdomain_task =
        Task.async(fn ->
          results = Subdomain.discover(slug)

          if broadcast?,
            do: broadcast(session_id, :layer_complete, %{layer: :subdomain, hits: results})

          {:subdomain, results}
        end)

      # Collect results
      [{:dns, dns_hits}, {:subdomain, subdomain_hits}] =
        [dns_task, subdomain_task]
        |> Task.await_many(30_000)

      # Merge and deduplicate hits
      all_hits = merge_hits(dns_hits, subdomain_hits)

      # Enrich with provider metadata
      enriched_hits = Enum.map(all_hits, &enrich_hit/1)

      completed_at = DateTime.utc_now()
      duration_ms = DateTime.diff(completed_at, started_at, :millisecond)

      report = %{
        email: email,
        domain: domain,
        slug: slug,
        started_at: started_at,
        completed_at: completed_at,
        duration_ms: duration_ms,
        hits: enriched_hits,
        layers_completed: [:dns, :subdomain],
        total_providers_checked: ProviderRegistry.count()
      }

      if broadcast?, do: broadcast(session_id, :discovery_complete, report)

      Logger.info(
        "Discovery complete for #{domain}: found #{length(enriched_hits)} providers in #{duration_ms}ms"
      )

      {:ok, report}
    end
  end

  @doc "Subscribe to real-time discovery events for a session."
  @spec subscribe(String.t()) :: :ok | {:error, term()}
  def subscribe(session_id) do
    Phoenix.PubSub.subscribe(@pubsub, "#{@topic_prefix}:#{session_id}")
  end

  @doc "Generate a unique session ID for pubsub."
  @spec generate_session_id() :: String.t()
  def generate_session_id do
    :crypto.strong_rand_bytes(16) |> Base.url_encode64(padding: false)
  end

  # ── Internal ──

  defp extract_domain(email) do
    case String.split(email, "@") do
      [_user, domain] when byte_size(domain) > 0 -> {:ok, String.downcase(domain)}
      _ -> {:error, :invalid_email}
    end
  end

  defp merge_hits(dns_hits, subdomain_hits) do
    # Convert subdomain results to common shape
    normalized_subdomain =
      Enum.map(subdomain_hits, fn hit ->
        %{
          provider_id: hit.provider_id,
          provider_name: hit.provider_name,
          detection_method: :subdomain,
          evidence: hit.url,
          confidence: hit.confidence
        }
      end)

    # Merge, preferring higher confidence
    (dns_hits ++ normalized_subdomain)
    |> Enum.group_by(& &1.provider_id)
    |> Enum.map(fn {_id, hits} ->
      # Take the hit with highest confidence
      Enum.min_by(hits, fn hit ->
        case hit.confidence do
          :high -> 0
          :medium -> 1
          :low -> 2
        end
      end)
    end)
  end

  defp enrich_hit(hit) do
    case ProviderRegistry.get(hit.provider_id) do
      nil ->
        Map.merge(hit, %{category: :unknown, auth_type: :unknown, icon: "unknown", color: "#666"})

      provider ->
        Map.merge(hit, %{
          category: provider.category,
          auth_type: provider.auth_type,
          icon: provider.icon,
          color: provider.color
        })
    end
  end

  defp broadcast(session_id, event, payload) do
    Phoenix.PubSub.broadcast(@pubsub, "#{@topic_prefix}:#{session_id}", {event, payload})
  end
end
