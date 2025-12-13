ExUnit.start()

# Configure ExUnit:
# - capture_log: true - suppress log output during tests (cleaner output)
# - exclude: skip slow and property tests by default
# - seed: 0 - deterministic test order
ExUnit.configure(
  capture_log: true,
  exclude: [property: true, slow: true],
  seed: 0
)
