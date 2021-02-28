import Config

secret_key_base =
  System.get_env("SECRET_KEY_BASE") ||
    raise """
    environment variable SECRET_KEY_BASE is missing.
    You can generate one by calling: mix phx.gen.secret
    """

if String.length(secret_key_base) < 64 do
  raise """
  environment variable SECRET_KEY_BASE is must be 64 bytes or longer!
  You can generate one by calling: mix phx.gen.secret
  """
end

server_url =
  System.get_env("SERVER_URL") ||
    raise """
    environment variable SERVER_URL is missing.
    For example: https://example.com:433
    """
server_url = URI.parse(server_url)

config :warehouse, WarehouseWeb.Endpoint,
  server: true,
  http: [
    port: String.to_integer(System.get_env("PORT") || "4000"),
    transport_options: [socket_opts: [:inet6]]
  ],
  url: [
    scheme: server_url.scheme,
    host: server_url.host,
    port: server_url.port,
    path: server_url.path
  ],
  secret_key_base: secret_key_base,
  live_view: [signing_salt: (fn s ->
    len = String.length(s)
    String.slice(s, max(0, min(div(len, 3), len - 10)), 10)
  end).(secret_key_base)]

# ## Using releases (Elixir v1.9+)
#
# If you are doing OTP releases, you need to instruct Phoenix
# to start each relevant endpoint:
#
#     config :repository, RepositoryWeb.Endpoint, server: true
#
# Then you can assemble a release by calling `mix release`.
# See `mix help release` for more information.
