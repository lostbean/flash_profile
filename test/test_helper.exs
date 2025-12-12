ExUnit.start()

# Configure StreamData for property-based testing
ExUnit.configure(exclude: [property: true], seed: 0)
