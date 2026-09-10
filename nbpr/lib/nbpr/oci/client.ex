defmodule NBPR.OCI.Client do
  @moduledoc false

  alias NBPR.Artifact.HTTP

  def parse_prefix!(prefix) when is_binary(prefix) do
    uri = URI.parse(if String.contains?(prefix, "://"), do: prefix, else: "https://" <> prefix)
    namespace = String.trim_leading(uri.path || "", "/")

    unless uri.scheme in ["http", "https"] and is_binary(uri.host) and uri.host != "" and
             is_nil(uri.userinfo) and is_nil(uri.query) and is_nil(uri.fragment) and
             Regex.match?(
               ~r/\A[a-z0-9]+(?:(?:[._]|__|-+)[a-z0-9]+)*(?:\/[a-z0-9]+(?:(?:[._]|__|-+)[a-z0-9]+)*)*\z/,
               namespace
             ) do
      raise ArgumentError,
            "registry must be a host/<owner>[/<path>] prefix (optionally with http:// or https://)"
    end

    {URI.to_string(%{uri | path: nil}), namespace}
  end

  def parse_prefix!(_), do: raise(ArgumentError, "registry must be a host/<owner> prefix")

  def new(prefix, package, actions \\ "pull") do
    {base, namespace} = parse_prefix!(prefix)
    image = "#{namespace}/#{package}"

    # These credentials belong only to the consuming project's registry;
    # never send them to a package's upstream fallback registry.
    credentials =
      if Application.get_env(:nbpr, :registry) == prefix do
        case {System.get_env("NBPR_REGISTRY_USERNAME"), System.get_env("NBPR_REGISTRY_TOKEN")} do
          {username, token} when is_binary(username) and is_binary(token) -> {username, token}
          {nil, nil} -> nil
          _ -> raise ArgumentError, "set both NBPR_REGISTRY_USERNAME and NBPR_REGISTRY_TOKEN"
        end
      end

    %{base: base, image: image, scope: "repository:#{image}:#{actions}", credentials: credentials}
  end

  # Resolve authentication before sending potentially large upload bodies.
  def authorize(client) do
    HTTP.start_apps!()

    case raw(:get, client.base <> "/v2/", [], nil) do
      {:ok, 200, _, _} ->
        {:ok, client}

      {:ok, 401, headers, _} ->
        with {:ok, auth} <- authenticate(client, header(headers, "www-authenticate")) do
          {:ok, Map.put(client, :authorization, auth)}
        end

      {:ok, status, _, _} ->
        {:error, {:registry_auth_http, status}}

      error ->
        error
    end
  end

  def request(client, method, path, headers \\ [], body \\ nil) do
    HTTP.start_apps!()
    url = URI.merge(client.base, path) |> URI.to_string()

    # Upload locations may be absolute. Do not answer authentication challenges
    # on a different origin using the project's credentials.
    if same_origin?(url, client.base) do
      authenticated_headers =
        if client[:authorization],
          do: [{"authorization", client.authorization} | headers],
          else: headers

      case raw(method, url, authenticated_headers, body) do
        {:ok, 401, response_headers, _} ->
          with {:ok, auth} <- authenticate(client, header(response_headers, "www-authenticate")) do
            raw(method, url, [{"authorization", auth} | headers], body)
          end

        result ->
          result
      end
    else
      {:error, :cross_origin_registry_request}
    end
  end

  def header(headers, name) do
    Enum.find_value(headers, fn {key, value} ->
      if String.downcase(to_string(key)) == name, do: to_string(value)
    end)
  end

  defp authenticate(client, challenge) when is_binary(challenge) do
    case String.split(challenge, " ", parts: 2) do
      [scheme, params] ->
        case String.downcase(scheme) do
          "basic" -> basic(client.credentials)
          "bearer" -> bearer(client, params)
          _ -> {:error, :unsupported_registry_auth}
        end

      _ ->
        {:error, :malformed_registry_auth}
    end
  end

  defp authenticate(_, _), do: {:error, :missing_registry_auth_challenge}

  defp basic(nil), do: {:error, :registry_credentials_required}
  defp basic({username, token}), do: {:ok, "Basic " <> Base.encode64("#{username}:#{token}")}

  defp bearer(client, params) do
    params =
      Regex.scan(~r/([a-zA-Z_]+)="([^"]*)"/, params)
      |> Map.new(fn [_, key, value] -> {String.downcase(key), value} end)

    realm = params["realm"]

    # Forgejo serves its token endpoint on the registry origin. Restricting
    # credential exchange to it prevents a challenge from leaking secrets.
    if is_binary(realm) and same_origin?(realm, client.base) do
      uri = URI.parse(realm)
      query = URI.decode_query(uri.query || "")
      query = Map.merge(query, %{"scope" => client.scope})
      query = if params["service"], do: Map.put(query, "service", params["service"]), else: query
      url = URI.to_string(%{uri | query: URI.encode_query(query)})

      headers =
        case basic(client.credentials) do
          {:ok, auth} -> [{"authorization", auth}]
          _ -> []
        end

      case raw(:get, url, headers, nil) do
        {:ok, 200, _, body} -> decode_token(body)
        {:ok, status, _, _} -> {:error, {:token_http, status}}
        error -> error
      end
    else
      {:error, :untrusted_registry_auth_realm}
    end
  end

  defp decode_token(body) do
    decoded = :json.decode(body)

    case decoded["token"] || decoded["access_token"] do
      token when is_binary(token) and token != "" -> {:ok, "Bearer " <> token}
      _ -> {:error, :token_missing}
    end
  rescue
    _ -> {:error, :invalid_token_response}
  end

  defp same_origin?(left, right) do
    a = URI.parse(left)
    b = URI.parse(right)
    {a.scheme, a.host, a.port} == {b.scheme, b.host, b.port} and is_nil(a.userinfo)
  end

  defp raw(method, url, headers, body) do
    headers = Enum.map(headers, fn {k, v} -> {to_charlist(k), to_charlist(v)} end)

    request =
      case body do
        nil -> {to_charlist(url), headers}
        {type, data} -> {to_charlist(url), headers, to_charlist(type), data}
      end

    case :httpc.request(
           method,
           request,
           [autoredirect: false, timeout: 120_000, connect_timeout: 15_000],
           body_format: :binary
         ) do
      {:ok, {{_, status, _}, response_headers, data}} -> {:ok, status, response_headers, data}
      {:error, reason} -> {:error, {:registry_http, reason}}
    end
  end
end
