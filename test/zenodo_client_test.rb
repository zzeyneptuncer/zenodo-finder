# frozen_string_literal: true

require "minitest/autorun"
load "./app.rb"

class ZenodoClientTest < Minitest::Test
  def setup
    @client = ZenodoClient.new
    @records = [
      { "metadata" => { "title" => "Drone image dataset", "description" => "Aerial imagery" } },
      { "metadata" => { "title" => "Audio samples", "description" => "Acoustic recordings" } },
      { "metadata" => { "title" => "IMU measurements", "description" => "Accelerometer sensor data" } }
    ]
  end

  def test_filter_by_type_returns_only_sensor_records
    result = @client.filter_by_type(@records, "Sensör")

    assert_equal 1, result.length
    assert_equal "IMU measurements", result.first.dig("metadata", "title")
  end
end
