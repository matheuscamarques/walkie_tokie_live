import Config

config :appsignal, :config,
  otp_app: :walkie_tokie,
  name: "walkie_tokie",
  push_api_key: "68099d63-3023-409f-b869-181e6e493d16",
  env: Mix.env()
