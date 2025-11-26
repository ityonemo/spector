import Config

if config_env() == :test do
  config :postgrex, :json_library, JSON
end
