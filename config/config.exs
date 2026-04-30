import Config

# Enable the Nerves integration with Mix so per-target dep filtering works
# and `Nerves.Env.system/0` resolves the active system.
Application.start(:nerves_bootstrap)

config :nbpr_workspace, target: Mix.target()
