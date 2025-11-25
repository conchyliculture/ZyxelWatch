require 'prometheus/client'
require 'prometheus/middleware/exporter'
require 'rack'
require 'rackup'
require 'webrick'
require 'json'

require_relative "client"

# --- 2. The Metric Updater Middleware ---
class ZyxelMetricUpdater
  def initialize(app, zyxel_instance, tx_gauge, rx_gauge, crc_gauge)
    @app = app
    @zyxel = zyxel_instance
    @tx_gauge = tx_gauge
    @rx_gauge = rx_gauge
    @crc_gauge = crc_gauge
  end

  def call(env)
    # Only trigger the update logic if the request is for /metrics
    if env['PATH_INFO'] == '/metrics'
      update_metrics
    end

    # Continue the request chain (hand over to Prometheus Exporter)
    @app.call(env)
  end

  private

  def update_metrics
    # 1. Get data (ONE call per scrape)
    data = @zyxel.get_ports_info()

    # 2. Update metrics programmatically
    data.each do |port_id, stats|
      # Labels must be symbols or strings
      labels = {
        port: port_id.to_s,
        name: ENV["ZYXEL_PORT_#{port_id}"] || "Port #{port_id}"
      }

      @tx_gauge.set(stats[:tx_packets], labels: labels)
      @rx_gauge.set(stats[:rx_packets], labels: labels)
      @crc_gauge.set(stats[:crc_errors], labels: labels)
    end
  end
end

# --- 3. Setup and Run ---

# Initialize Registry and Metrics
registry = Prometheus::Client.registry

# Define Gauges with a 'port' label
tx_packets = Prometheus::Client::Gauge.new(
  :zyxel_port_tx_packets,
  docstring: 'Transmitted bytes per port',
  labels: [:port, :name]
)
rx_packets = Prometheus::Client::Gauge.new(
  :zyxel_port_rx_packets,
  docstring: 'Received bytes per port',
  labels: [:port, :name]
)

crc_errors = Prometheus::Client::Gauge.new(
  :zyxel_port_crc_errors,
  docstring: 'CRC errors per port',
  labels: [:port, :name]
)

# Register them
registry.register(tx_packets)
registry.register(rx_packets)
registry.register(crc_errors)

# Initialize your object
zyxel_device = XGS1210Api.new(ENV['ZYXEL_HOST'], ENV['ZYXEL_PASSWORD'])

# Configure Rack App
app = Rack::Builder.new do
  use Rack::Deflater

  # VITAL: This middleware must come BEFORE the Exporter.
  # It updates the values, then passes the request to the Exporter.
  use ZyxelMetricUpdater, zyxel_device, tx_packets, rx_packets, crc_errors

  # The standard exporter that renders the text format
  use Prometheus::Middleware::Exporter, registry: registry

  # Fallback for other routes
  run ->(_) { [200, { 'Content-Type' => 'text/plain' }, ['Zyxel Exporter Running...']] }
end

# Start Server on port 9292
puts "Server running on http://localhost:4567/metrics"
Rackup::Handler::WEBrick.run(app, Port: 4567, Host: '0.0.0.0')
