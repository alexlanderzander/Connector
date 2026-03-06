defmodule ConnectorWeb.DiscoveryLive do
  @moduledoc """
  LiveView for the SaaS stack discovery experience.

  The user enters their work email, and the discovery engine runs
  all layers simultaneously while the UI updates in real-time
  showing each detected service as it's found.
  """

  use ConnectorWeb, :live_view

  alias Connector.Discovery.Orchestrator

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:email, "")
     |> assign(:state, :idle)
     |> assign(:hits, [])
     |> assign(:layers_completed, [])
     |> assign(:duration_ms, nil)
     |> assign(:error, nil)
     |> assign(:session_id, nil)
     |> assign(:total_checked, 0)}
  end

  @impl true
  def handle_event("update_email", %{"email" => email}, socket) do
    {:noreply, assign(socket, :email, email)}
  end

  @impl true
  def handle_event("discover", %{"email" => email}, socket) do
    email = String.trim(email)

    if valid_email?(email) do
      session_id = Orchestrator.generate_session_id()
      Orchestrator.subscribe(session_id)

      # Run discovery in background task
      Task.start(fn ->
        Orchestrator.run(email, session_id: session_id)
      end)

      {:noreply,
       socket
       |> assign(:email, email)
       |> assign(:state, :discovering)
       |> assign(:hits, [])
       |> assign(:layers_completed, [])
       |> assign(:error, nil)
       |> assign(:session_id, session_id)}
    else
      {:noreply, assign(socket, :error, "Please enter a valid work email address")}
    end
  end

  # ── PubSub event handlers ──

  @impl true
  def handle_info({:discovery_started, _payload}, socket) do
    {:noreply, assign(socket, :state, :discovering)}
  end

  @impl true
  def handle_info({:layer_complete, %{layer: layer, hits: new_hits}}, socket) do
    existing_ids = MapSet.new(socket.assigns.hits, & &1.provider_id)

    unique_new =
      new_hits
      |> Enum.reject(fn hit -> MapSet.member?(existing_ids, hit.provider_id) end)
      |> Enum.map(&normalize_hit/1)

    {:noreply,
     socket
     |> assign(:hits, socket.assigns.hits ++ unique_new)
     |> assign(:layers_completed, [layer | socket.assigns.layers_completed])}
  end

  @impl true
  def handle_info({:discovery_complete, report}, socket) do
    {:noreply,
     socket
     |> assign(:state, :complete)
     |> assign(:hits, report.hits)
     |> assign(:duration_ms, report.duration_ms)
     |> assign(:total_checked, report.total_providers_checked)}
  end

  @impl true
  def handle_info(_msg, socket), do: {:noreply, socket}

  # ── Template ──

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gradient-to-br from-slate-950 via-slate-900 to-indigo-950 text-white">
      <!-- Hero Section -->
      <div class="max-w-4xl mx-auto px-6 pt-20 pb-12">
        <div class="text-center mb-12">
          <div class="inline-flex items-center gap-2 px-4 py-2 rounded-full bg-indigo-500/10 border border-indigo-500/20 text-indigo-300 text-sm mb-8">
            <span class="relative flex h-2 w-2">
              <span class="animate-ping absolute inline-flex h-full w-full rounded-full bg-indigo-400 opacity-75">
              </span>
              <span class="relative inline-flex rounded-full h-2 w-2 bg-indigo-500"></span>
            </span>
            Powered by AI Discovery
          </div>
          <h1 class="text-5xl font-bold tracking-tight mb-4">
            <span class="bg-gradient-to-r from-white via-indigo-200 to-indigo-400 bg-clip-text text-transparent">
              Connector
            </span>
          </h1>
          <p class="text-xl text-slate-400 max-w-2xl mx-auto">
            Enter your work email. We'll discover your company's SaaS stack
            and connect everything in one click.
          </p>
        </div>
        
    <!-- Email Input -->
        <form phx-submit="discover" class="max-w-xl mx-auto mb-16">
          <div class="flex gap-3">
            <div class="flex-1 relative">
              <input
                type="email"
                name="email"
                value={@email}
                placeholder="you@company.com"
                phx-change="update_email"
                class="w-full px-6 py-4 rounded-2xl bg-white/5 border border-white/10 text-white
                       placeholder-slate-500 text-lg focus:outline-none focus:ring-2 focus:ring-indigo-500/50
                       focus:border-indigo-500/50 transition-all duration-200"
                autocomplete="email"
                disabled={@state == :discovering}
              />
            </div>
            <button
              type="submit"
              disabled={@state == :discovering || @email == ""}
              class={"px-8 py-4 rounded-2xl font-semibold text-lg transition-all duration-200
                     #{if @state == :discovering, do: "bg-indigo-600/50 cursor-wait", else: "bg-indigo-600 hover:bg-indigo-500 hover:shadow-lg hover:shadow-indigo-500/25 active:scale-95"}"}
            >
              <%= if @state == :discovering do %>
                <span class="flex items-center gap-2">
                  <svg
                    class="animate-spin h-5 w-5"
                    xmlns="http://www.w3.org/2000/svg"
                    fill="none"
                    viewBox="0 0 24 24"
                  >
                    <circle
                      class="opacity-25"
                      cx="12"
                      cy="12"
                      r="10"
                      stroke="currentColor"
                      stroke-width="4"
                    >
                    </circle>
                    <path
                      class="opacity-75"
                      fill="currentColor"
                      d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"
                    >
                    </path>
                  </svg>
                  Scanning...
                </span>
              <% else %>
                Discover
              <% end %>
            </button>
          </div>

          <%= if @error do %>
            <p class="mt-3 text-red-400 text-sm">{@error}</p>
          <% end %>
        </form>
        
    <!-- Progress Indicator -->
        <%= if @state in [:discovering, :complete] do %>
          <div class="mb-8">
            <div class="flex items-center justify-between text-sm text-slate-400 mb-3">
              <span>
                <%= if @state == :discovering do %>
                  Scanning discovery layers...
                <% else %>
                  Discovery complete
                <% end %>
              </span>
              <span>
                {length(@hits)} services found
                <%= if @duration_ms do %>
                  · {@duration_ms}ms
                <% end %>
              </span>
            </div>
            
    <!-- Layer progress pills -->
            <div class="flex gap-2 mb-8">
              <.layer_pill name="DNS Records" layer={:dns} completed={@layers_completed} />
              <.layer_pill name="Subdomain Probe" layer={:subdomain} completed={@layers_completed} />
              <.layer_pill name="IdP Discovery" layer={:idp} completed={@layers_completed} />
            </div>
          </div>
          
    <!-- Discovered Services Grid -->
          <%= if @hits != [] do %>
            <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
              <%= for hit <- @hits do %>
                <.service_card hit={hit} />
              <% end %>
            </div>
            
    <!-- Connect All CTA -->
            <%= if @state == :complete do %>
              <div class="mt-12 text-center">
                <button class="px-12 py-5 rounded-2xl font-bold text-xl bg-gradient-to-r from-indigo-600 to-purple-600
                               hover:from-indigo-500 hover:to-purple-500 transition-all duration-200
                               shadow-lg shadow-indigo-500/25 hover:shadow-xl hover:shadow-indigo-500/30
                               active:scale-95">
                  Connect All {length(@hits)} Services →
                </button>
                <p class="mt-4 text-slate-500 text-sm">
                  Our AI agent will handle credentials and setup for each service
                </p>
              </div>
            <% end %>
          <% else %>
            <%= if @state == :complete do %>
              <div class="text-center py-12 text-slate-500">
                <p class="text-lg">No services detected for this domain.</p>
                <p class="text-sm mt-2">Try a different email address, or manually add services.</p>
              </div>
            <% end %>
          <% end %>
        <% end %>
      </div>
    </div>
    """
  end

  # ── Components ──

  defp layer_pill(assigns) do
    completed? = assigns.layer in assigns.completed

    assigns =
      assigns
      |> assign(:completed?, completed?)
      |> assign(
        :classes,
        if(completed?,
          do: "bg-green-500/10 border-green-500/30 text-green-400",
          else: "bg-white/5 border-white/10 text-slate-500"
        )
      )

    ~H"""
    <span class={"inline-flex items-center gap-1.5 px-3 py-1.5 rounded-full border text-xs font-medium transition-all duration-500 #{@classes}"}>
      <%= if @completed? do %>
        <svg class="w-3.5 h-3.5" fill="currentColor" viewBox="0 0 20 20">
          <path
            fill-rule="evenodd"
            d="M16.707 5.293a1 1 0 010 1.414l-8 8a1 1 0 01-1.414 0l-4-4a1 1 0 011.414-1.414L8 12.586l7.293-7.293a1 1 0 011.414 0z"
            clip-rule="evenodd"
          />
        </svg>
      <% else %>
        <svg class="w-3.5 h-3.5 animate-spin" fill="none" viewBox="0 0 24 24">
          <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4">
          </circle>
          <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4z">
          </path>
        </svg>
      <% end %>
      {@name}
    </span>
    """
  end

  defp service_card(assigns) do
    confidence_color =
      case assigns.hit.confidence do
        :high -> "text-green-400"
        :medium -> "text-yellow-400"
        :low -> "text-slate-500"
      end

    category_label =
      case assigns.hit[:category] do
        :hr -> "HR"
        :mdm -> "MDM"
        :identity -> "Identity"
        :crm -> "CRM"
        :communication -> "Communication"
        :productivity -> "Productivity"
        :finance -> "Finance"
        _ -> "Service"
      end

    assigns =
      assigns
      |> assign(:confidence_color, confidence_color)
      |> assign(:category_label, category_label)

    ~H"""
    <div class="group p-5 rounded-2xl bg-white/5 border border-white/10 hover:border-indigo-500/30
                hover:bg-white/[0.07] transition-all duration-300 animate-fade-in">
      <div class="flex items-start justify-between">
        <div class="flex items-center gap-3">
          <div
            class="w-10 h-10 rounded-xl flex items-center justify-center text-white font-bold text-sm"
            style={"background-color: #{@hit.color}20; color: #{@hit.color}"}
          >
            {String.first(@hit.provider_name)}
          </div>
          <div>
            <h3 class="font-semibold text-white">{@hit.provider_name}</h3>
            <span class="text-xs text-slate-500">{@category_label}</span>
          </div>
        </div>
        <span class={"text-xs font-medium #{@confidence_color}"}>
          {@hit.confidence}
        </span>
      </div>
      <div class="mt-3 text-xs text-slate-500 font-mono truncate">
        {@hit.evidence}
      </div>
    </div>
    """
  end

  # ── Helpers ──

  defp valid_email?(email) do
    String.contains?(email, "@") and String.contains?(email, ".")
  end

  defp normalize_hit(hit) do
    provider = Connector.Discovery.ProviderRegistry.get(hit.provider_id)

    %{
      provider_id: hit.provider_id,
      provider_name: hit.provider_name,
      detection_method: hit.detection_method,
      evidence: Map.get(hit, :evidence) || Map.get(hit, :url) || "detected",
      confidence: hit.confidence,
      category: if(provider, do: provider.category, else: :unknown),
      auth_type: if(provider, do: provider.auth_type, else: :unknown),
      icon: if(provider, do: provider.icon, else: "unknown"),
      color: if(provider, do: provider.color, else: "#666666")
    }
  end
end
