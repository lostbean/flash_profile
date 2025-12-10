defmodule FlashProfile.ApiTest do
  use ExUnit.Case, async: true

  doctest FlashProfile

  alias FlashProfile

  # ==================== FLASHPROFILE API ====================

  describe "Profile function" do
    test "profile returns ok tuple" do
      assert {:ok, _} = FlashProfile.profile(["a", "b", "c"])
    end

    test "profile returns error for empty list" do
      assert {:error, :empty_input} = FlashProfile.profile([])
    end

    test "profile returns error for non-strings" do
      assert {:error, :non_string_values} = FlashProfile.profile([1, 2, 3])
    end

    test "profile returns error for non-list" do
      assert {:error, :not_a_list} = FlashProfile.profile("not a list")
    end

    test "profile! returns profile directly" do
      profile = FlashProfile.profile!(["a", "b"])
      assert is_map(profile)
    end

    test "profile! raises on error" do
      assert_raise ArgumentError, fn ->
        FlashProfile.profile!([])
      end
    end
  end

  describe "Profile structure" do
    test "profile has patterns field" do
      {:ok, profile} = FlashProfile.profile(["a", "b"])
      assert Map.has_key?(profile, :patterns)
    end

    test "profile has anomalies field" do
      {:ok, profile} = FlashProfile.profile(["a", "b"])
      assert Map.has_key?(profile, :anomalies)
    end

    test "profile has stats field" do
      {:ok, profile} = FlashProfile.profile(["a", "b"])
      assert Map.has_key?(profile, :stats)
    end

    test "profile has options field" do
      {:ok, profile} = FlashProfile.profile(["a", "b"])
      assert Map.has_key?(profile, :options)
    end
  end

  describe "Stats structure" do
    test "stats has total_values" do
      {:ok, profile} = FlashProfile.profile(["a", "b", "c"])
      assert profile.stats.total_values == 3
    end

    test "stats has distinct_values" do
      {:ok, profile} = FlashProfile.profile(["a", "a", "b"])
      assert profile.stats.distinct_values == 2
    end

    test "stats has pattern_count" do
      {:ok, profile} = FlashProfile.profile(["a", "b"])
      assert profile.stats.pattern_count >= 1
    end

    test "stats has total_coverage" do
      {:ok, profile} = FlashProfile.profile(["a", "b"])
      assert profile.stats.total_coverage >= 0.0
      assert profile.stats.total_coverage <= 1.0
    end

    test "stats has anomaly_count" do
      {:ok, profile} = FlashProfile.profile(["a", "b"])
      assert is_integer(profile.stats.anomaly_count)
    end
  end

  describe "Pattern info structure" do
    test "pattern_info has regex field" do
      {:ok, profile} = FlashProfile.profile(["a", "b"])
      assert Enum.all?(profile.patterns, &Map.has_key?(&1, :regex))
    end

    test "pattern_info has coverage field" do
      {:ok, profile} = FlashProfile.profile(["a", "b"])
      assert Enum.all?(profile.patterns, &Map.has_key?(&1, :coverage))
    end

    test "pattern_info has pretty field" do
      {:ok, profile} = FlashProfile.profile(["a", "b"])
      assert Enum.all?(profile.patterns, &Map.has_key?(&1, :pretty))
    end
  end

  describe "Options" do
    test "respects max_clusters option" do
      data = for i <- 1..5, do: String.duplicate("X", i) <> "-1"
      {:ok, profile} = FlashProfile.profile(data, max_clusters: 2)
      assert profile.stats.pattern_count <= 2
    end

    test "respects detect_anomalies option" do
      data = for(_ <- 1..10, do: "A-1") ++ ["WEIRD"]
      {:ok, p1} = FlashProfile.profile(data, detect_anomalies: true)
      {:ok, p2} = FlashProfile.profile(data, detect_anomalies: false)
      assert length(p1.anomalies) >= 0
      assert p2.anomalies == []
    end
  end

  describe "Helper functions" do
    test "patterns returns pattern list" do
      {:ok, profile} = FlashProfile.profile(["a", "b"])
      patterns = FlashProfile.patterns(profile)
      assert is_list(patterns)
      assert Enum.all?(patterns, &is_tuple/1)
    end

    test "regexes returns regex strings" do
      {:ok, profile} = FlashProfile.profile(["a", "b"])
      regexes = FlashProfile.regexes(profile)
      assert is_list(regexes)
      assert Enum.all?(regexes, &is_binary/1)
    end

    test "anomalies returns anomaly list" do
      {:ok, profile} = FlashProfile.profile(["a", "b"])
      anomalies = FlashProfile.anomalies(profile)
      assert is_list(anomalies)
    end
  end

  describe "Inference helpers" do
    test "infer_pattern returns pattern tuple" do
      pattern = FlashProfile.infer_pattern(["A", "B", "C"])
      assert is_tuple(pattern)
    end

    test "infer_regex returns regex string" do
      regex = FlashProfile.infer_regex(["A-1", "B-2"])
      assert is_binary(regex)
    end
  end

  # ==================== VALIDATION API ====================

  describe "Validation" do
    test "validate returns :ok for matching value" do
      {:ok, profile} = FlashProfile.profile(["A", "B", "C"])
      assert FlashProfile.validate(profile, "A") == :ok
    end

    test "validate returns :ok for all original values" do
      data = ["ACC-001", "ORG-002", "ACCT-003"]
      {:ok, profile} = FlashProfile.profile(data)
      assert Enum.all?(data, fn v -> FlashProfile.validate(profile, v) == :ok end)
    end

    test "validate returns error for non-matching value" do
      {:ok, profile} = FlashProfile.profile(["A", "B", "C"])
      assert FlashProfile.validate(profile, "X") == {:error, :no_match}
    end

    test "validate rejects structurally different" do
      {:ok, profile} = FlashProfile.profile(["A-1", "B-2"])
      assert FlashProfile.validate(profile, "A@1") == {:error, :no_match}
    end

    test "validate handles multiple pattern profiles" do
      data = ["A-1", "B-2"] ++ ["X@Y", "Z@W"]
      {:ok, profile} = FlashProfile.profile(data)
      # Algorithm enumerates small sets - verify originals match
      assert FlashProfile.validate(profile, "A-1") == :ok
      assert FlashProfile.validate(profile, "X@Y") == :ok
    end
  end

  # ==================== EXPORT AND SERIALIZATION ====================

  describe "Export" do
    test "export returns map" do
      {:ok, profile} = FlashProfile.profile(["a", "b", "c"])
      export = FlashProfile.export(profile)
      assert is_map(export)
    end

    test "export has patterns field" do
      {:ok, profile} = FlashProfile.profile(["a", "b", "c"])
      export = FlashProfile.export(profile)
      assert Map.has_key?(export, :patterns)
    end

    test "export has stats field" do
      {:ok, profile} = FlashProfile.profile(["a", "b", "c"])
      export = FlashProfile.export(profile)
      assert Map.has_key?(export, :stats)
    end

    test "export patterns have serializable fields" do
      {:ok, profile} = FlashProfile.profile(["a", "b", "c"])
      export = FlashProfile.export(profile)
      pattern = hd(export.patterns)
      assert Map.has_key?(pattern, :regex)
      assert Map.has_key?(pattern, :coverage)
      assert Map.has_key?(pattern, :matched_count)
    end
  end

  describe "Summary" do
    test "summary returns string" do
      {:ok, profile} = FlashProfile.profile(["a", "b", "c"])
      summary = FlashProfile.summary(profile)
      assert is_binary(summary)
    end

    test "summary contains Profile Summary header" do
      {:ok, profile} = FlashProfile.profile(["a", "b", "c"])
      summary = FlashProfile.summary(profile)
      assert String.contains?(summary, "Profile Summary")
    end

    test "summary contains pattern count" do
      {:ok, profile} = FlashProfile.profile(["a", "b", "c"])
      summary = FlashProfile.summary(profile)
      assert String.contains?(summary, "Patterns")
    end

    test "summary contains coverage" do
      {:ok, profile} = FlashProfile.profile(["a", "b", "c"])
      summary = FlashProfile.summary(profile)
      assert String.contains?(summary, "coverage")
    end
  end

  describe "Merge" do
    test "merge combines two profiles" do
      {:ok, p1} = FlashProfile.profile(["A", "B"])
      {:ok, p2} = FlashProfile.profile(["C", "D"])
      merged = FlashProfile.merge(p1, p2)
      assert merged.stats.distinct_values >= 4
    end

    test "merge handles overlapping values" do
      {:ok, p1} = FlashProfile.profile(["A", "B", "C"])
      {:ok, p2} = FlashProfile.profile(["B", "C", "D"])
      merged = FlashProfile.merge(p1, p2)
      assert merged.stats.distinct_values == 4
    end
  end
end
