ExUnit.start()

# Configure StreamData for property-based testing
# Exclude slow tests (like IPv4 with 5000+ strings) by default
ExUnit.configure(exclude: [property: true, slow: true], seed: 0)
