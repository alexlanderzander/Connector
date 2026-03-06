defmodule Connector.Discovery.ProviderRegistry do
  @moduledoc """
  Registry of known SaaS providers and their detection fingerprints.

  Each provider entry contains:
  - DNS fingerprints (MX, SPF, TXT patterns)
  - Subdomain patterns (e.g., "{domain}.bamboohr.com")
  - Well-known endpoint paths
  - Auth type and OAuth metadata
  - Category (hr, mdm, identity, crm, communication, etc.)
  """

  @type auth_type :: :oauth2 | :api_key | :basic | :jwt | :scim | :bearer
  @type category :: :hr | :mdm | :identity | :crm | :communication | :productivity | :finance

  @type provider :: %{
          id: atom(),
          name: String.t(),
          category: category(),
          auth_type: auth_type(),
          mx_contains: [String.t()],
          spf_includes: [String.t()],
          txt_contains: [String.t()],
          subdomain_templates: [String.t()],
          well_known_paths: [String.t()],
          oauth_config: map() | nil,
          api_base: String.t() | nil,
          icon: String.t(),
          color: String.t()
        }

  @doc "Get all registered providers."
  @spec all() :: %{atom() => provider()}
  def all, do: providers()

  @doc "Get a specific provider by ID."
  @spec get(atom()) :: provider() | nil
  def get(id), do: Map.get(providers(), id)

  @doc "Get all providers that can be detected via DNS (MX, SPF, TXT)."
  @spec dns_detectable() :: [provider()]
  def dns_detectable do
    providers()
    |> Map.values()
    |> Enum.filter(fn p ->
      p.mx_contains != [] or p.spf_includes != [] or p.txt_contains != []
    end)
  end

  @doc "Get all providers that can be detected via subdomain probing."
  @spec subdomain_detectable() :: [provider()]
  def subdomain_detectable do
    providers()
    |> Map.values()
    |> Enum.filter(fn p -> p.subdomain_templates != [] end)
  end

  @doc "Get all providers in a specific category."
  @spec by_category(category()) :: [provider()]
  def by_category(category) do
    providers()
    |> Map.values()
    |> Enum.filter(fn p -> p.category == category end)
  end

  @doc "Get the total number of registered providers."
  @spec count() :: non_neg_integer()
  def count, do: map_size(providers())

  # ── Provider Definitions ──

  defp providers do
    %{
      # ──────── Identity / Email ────────
      google_workspace: %{
        id: :google_workspace,
        name: "Google Workspace",
        category: :identity,
        auth_type: :oauth2,
        mx_contains: ["google.com", "googlemail.com"],
        spf_includes: ["_spf.google.com"],
        txt_contains: ["google-site-verification="],
        subdomain_templates: [],
        well_known_paths: [],
        oauth_config: %{
          authorize_url: "https://accounts.google.com/o/oauth2/v2/auth",
          token_url: "https://oauth2.googleapis.com/token",
          scopes: [
            "https://www.googleapis.com/auth/admin.directory.user.readonly",
            "https://www.googleapis.com/auth/admin.directory.device.chromeos.readonly"
          ]
        },
        api_base: "https://admin.googleapis.com",
        icon: "google",
        color: "#4285F4"
      },
      microsoft_365: %{
        id: :microsoft_365,
        name: "Microsoft 365",
        category: :identity,
        auth_type: :oauth2,
        mx_contains: ["outlook.com", "protection.outlook.com"],
        spf_includes: ["spf.protection.outlook.com"],
        txt_contains: ["MS=ms", "v=verifydomain"],
        subdomain_templates: [],
        well_known_paths: ["/.well-known/openid-configuration"],
        oauth_config: %{
          authorize_url: "https://login.microsoftonline.com/common/oauth2/v2.0/authorize",
          token_url: "https://login.microsoftonline.com/common/oauth2/v2.0/token",
          scopes: ["https://graph.microsoft.com/.default"]
        },
        api_base: "https://graph.microsoft.com/v1.0",
        icon: "microsoft",
        color: "#00A4EF"
      },

      # ──────── MDM ────────
      intune: %{
        id: :intune,
        name: "Microsoft Intune",
        category: :mdm,
        auth_type: :oauth2,
        mx_contains: [],
        spf_includes: [],
        txt_contains: [],
        subdomain_templates: [],
        well_known_paths: [],
        oauth_config: %{
          authorize_url: "https://login.microsoftonline.com/common/oauth2/v2.0/authorize",
          token_url: "https://login.microsoftonline.com/common/oauth2/v2.0/token",
          scopes: ["https://graph.microsoft.com/DeviceManagementManagedDevices.Read.All"]
        },
        api_base: "https://graph.microsoft.com/v1.0/deviceManagement",
        icon: "intune",
        color: "#0078D4"
      },
      kandji: %{
        id: :kandji,
        name: "Kandji",
        category: :mdm,
        auth_type: :bearer,
        mx_contains: [],
        spf_includes: [],
        txt_contains: [],
        subdomain_templates: ["{slug}.clients.us-1.kandji.io"],
        well_known_paths: [],
        oauth_config: nil,
        api_base: "https://{slug}.api.kandji.io/api/v1",
        icon: "kandji",
        color: "#1A1A2E"
      },
      jamf: %{
        id: :jamf,
        name: "Jamf Pro",
        category: :mdm,
        auth_type: :oauth2,
        mx_contains: [],
        spf_includes: [],
        txt_contains: [],
        subdomain_templates: ["{slug}.jamfcloud.com"],
        well_known_paths: [],
        oauth_config: %{
          token_url: "https://{slug}.jamfcloud.com/api/oauth/token"
        },
        api_base: "https://{slug}.jamfcloud.com/api/v1",
        icon: "jamf",
        color: "#6C2DC7"
      },
      mosyle: %{
        id: :mosyle,
        name: "Mosyle",
        category: :mdm,
        auth_type: :bearer,
        mx_contains: [],
        spf_includes: [],
        txt_contains: [],
        subdomain_templates: [],
        well_known_paths: [],
        oauth_config: nil,
        api_base: "https://managerapi.mosyle.com/v2",
        icon: "mosyle",
        color: "#00B4D8"
      },

      # ──────── HR ────────
      personio: %{
        id: :personio,
        name: "Personio",
        category: :hr,
        auth_type: :oauth2,
        mx_contains: [],
        spf_includes: ["_spf.personio.de"],
        txt_contains: [],
        subdomain_templates: ["{slug}.personio.de"],
        well_known_paths: [],
        oauth_config: %{token_url: "https://api.personio.de/v1/auth"},
        api_base: "https://api.personio.de/v2",
        icon: "personio",
        color: "#00B4A0"
      },
      bamboohr: %{
        id: :bamboohr,
        name: "BambooHR",
        category: :hr,
        auth_type: :api_key,
        mx_contains: [],
        spf_includes: [],
        txt_contains: [],
        subdomain_templates: ["{slug}.bamboohr.com"],
        well_known_paths: [],
        oauth_config: nil,
        api_base: "https://api.bamboohr.com/api/gateway.php/{slug}/v1",
        icon: "bamboohr",
        color: "#73C41D"
      },
      hibob: %{
        id: :hibob,
        name: "HiBob",
        category: :hr,
        auth_type: :basic,
        mx_contains: [],
        spf_includes: [],
        txt_contains: [],
        subdomain_templates: [],
        well_known_paths: [],
        oauth_config: nil,
        api_base: "https://api.hibob.com/v1",
        icon: "hibob",
        color: "#FF6B35"
      },

      # ──────── Communication ────────
      slack: %{
        id: :slack,
        name: "Slack",
        category: :communication,
        auth_type: :oauth2,
        mx_contains: [],
        spf_includes: [],
        txt_contains: [],
        subdomain_templates: ["{slug}.slack.com"],
        well_known_paths: [],
        oauth_config: %{
          authorize_url: "https://slack.com/oauth/v2/authorize",
          token_url: "https://slack.com/api/oauth.v2.access",
          scopes: ["users:read", "channels:read"]
        },
        api_base: "https://slack.com/api",
        icon: "slack",
        color: "#4A154B"
      },

      # ──────── Identity / SSO ────────
      okta: %{
        id: :okta,
        name: "Okta",
        category: :identity,
        auth_type: :oauth2,
        mx_contains: [],
        spf_includes: [],
        txt_contains: [],
        subdomain_templates: ["{slug}.okta.com"],
        well_known_paths: ["/.well-known/openid-configuration"],
        oauth_config: %{
          authorize_url: "https://{slug}.okta.com/oauth2/v1/authorize",
          token_url: "https://{slug}.okta.com/oauth2/v1/token"
        },
        api_base: "https://{slug}.okta.com/api/v1",
        icon: "okta",
        color: "#007DC1"
      },

      # ──────── CRM ────────
      hubspot: %{
        id: :hubspot,
        name: "HubSpot",
        category: :crm,
        auth_type: :oauth2,
        mx_contains: [],
        spf_includes: ["_spf.hubspot.com"],
        txt_contains: [],
        subdomain_templates: [],
        well_known_paths: [],
        oauth_config: %{
          authorize_url: "https://app.hubspot.com/oauth/authorize",
          token_url: "https://api.hubapi.com/oauth/v1/token"
        },
        api_base: "https://api.hubapi.com",
        icon: "hubspot",
        color: "#FF7A59"
      },
      salesforce: %{
        id: :salesforce,
        name: "Salesforce",
        category: :crm,
        auth_type: :oauth2,
        mx_contains: [],
        spf_includes: ["_spf.salesforce.com"],
        txt_contains: [],
        subdomain_templates: ["{slug}.my.salesforce.com", "{slug}.lightning.force.com"],
        well_known_paths: [],
        oauth_config: %{
          authorize_url: "https://login.salesforce.com/services/oauth2/authorize",
          token_url: "https://login.salesforce.com/services/oauth2/token"
        },
        api_base: "https://{slug}.my.salesforce.com/services/data/v59.0",
        icon: "salesforce",
        color: "#00A1E0"
      },

      # ──────── Productivity ────────
      atlassian: %{
        id: :atlassian,
        name: "Atlassian (Jira/Confluence)",
        category: :productivity,
        auth_type: :oauth2,
        mx_contains: [],
        spf_includes: [],
        txt_contains: ["atlassian-domain-verification"],
        subdomain_templates: ["{slug}.atlassian.net"],
        well_known_paths: [],
        oauth_config: %{
          authorize_url: "https://auth.atlassian.com/authorize",
          token_url: "https://auth.atlassian.com/oauth/token"
        },
        api_base: "https://api.atlassian.com",
        icon: "atlassian",
        color: "#0052CC"
      },
      notion: %{
        id: :notion,
        name: "Notion",
        category: :productivity,
        auth_type: :oauth2,
        mx_contains: [],
        spf_includes: [],
        txt_contains: [],
        subdomain_templates: [],
        well_known_paths: [],
        oauth_config: %{
          authorize_url: "https://api.notion.com/v1/oauth/authorize",
          token_url: "https://api.notion.com/v1/oauth/token"
        },
        api_base: "https://api.notion.com/v1",
        icon: "notion",
        color: "#000000"
      }
    }
  end
end
